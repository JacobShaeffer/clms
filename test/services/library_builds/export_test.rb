require "test_helper"
require_relative "../../support/library_build_helpers"

class LibraryBuilds::ExportTest < ActiveSupport::TestCase
  include LibraryBuildHelpers

  setup { setup_build_library }
  teardown { teardown_build_library }

  test "exports saved folders with current intrinsic fields metadata assets and files" do
    type = MetadataType.create!(name: "Future Taxonomy", user: @user)
    value = type.metadata.create!(name: "UniqueMetadataTerm", user: @user)
    @content.metadata << value
    build = request_export
    @content.update!(display_title: "New Display Title", description: "LatestDescription")
    @content.file.attach(io: StringIO.new("replaced bytes"), filename: "../../unsafe document.pdf", content_type: "application/pdf")
    @library.current_version.library_folders.find_by!(name: @root.name).update!(name: "Live Subject")
    @asset.image.attach(io: StringIO.new("new image bytes"), filename: "new.png", content_type: "image/png")
    mod = LibraryModule.create!(name: "Module", folder_name: "launch-destination", icon: @asset, user: @user)
    @library.selected_modules << mod
    run_export(build)

    storage = LibraryBuilds::Storage.new(build)
    assert_empty storage.folder_path.join("modules", "launch-destination").children
    export_db(build) do |db|
      assert_equal "Saved Subject", db.get_first_value("SELECT folder_name FROM folder WHERE id = ?", @root.id)
      assert_equal @root.id, db.get_first_value("SELECT parent_id FROM folder WHERE id = ?", @child.id)
      assert_equal "New Display Title", db.get_first_value("SELECT title FROM content")
      assert_equal 2024, db.get_first_value("SELECT year_of_publication FROM content")
      assert_equal 1, db.get_first_value("SELECT count(*) FROM content")
      assert_equal 2, db.get_first_value("SELECT count(*) FROM content_folder")
      assert_equal "launch-destination", db.get_first_value("SELECT module_name FROM module")
      %w[New LatestDescription UniqueMetadataTerm].each do |term|
        assert_equal [ [ @content.id ] ], db.execute("SELECT rowid FROM content_fts WHERE content_fts MATCH ?", term)
      end
      assert_equal [ [ "Future Taxonomy" ] ], db.execute("SELECT type_name FROM metadata_type")
      assert_equal [ [ value.id, "UniqueMetadataTerm" ] ], db.execute("SELECT id,meta_name FROM metadata")
      assert_equal [ [ @content.id, value.id ] ], db.execute("SELECT * FROM content_metadata")
      assert_equal %w[id title description file_name file_size year_of_publication additional_notes], db.execute("PRAGMA table_info(content)").map { |row| row[1] }
      assert_equal 1, db.get_first_value("PRAGMA user_version")
      assert_empty db.execute("PRAGMA foreign_key_check")
      filename = db.get_first_value("SELECT file_name FROM content")
      refute_includes filename, "/"
      assert_equal "replaced bytes", storage.folder_path.join("content", filename).read
      assert_equal "new image bytes", storage.folder_path.join(db.get_first_value("SELECT logo FROM folder WHERE parent_id IS NULL")).read
      assert_equal 1, storage.folder_path.join("assets").children.length
    end
    Zip::File.open(storage.archive_path) do |zip|
      assert zip.find_entry("export/library.db")
      assert zip.find_entry("export/content/")
      assert zip.find_entry("export/assets/")
      assert_predicate zip.find_entry("export/modules/launch-destination/"), :directory?
      assert_predicate zip.find_entry("export/modules/"), :directory?
      assert_equal 1, zip.entries.count { |entry| entry.name.start_with?("export/content/") && !entry.directory? }
    end
    assert_predicate build, :ready?
    assert_empty build.working_files
  end

  test "module folders use exact selected folder names and are replaced on rebuild" do
    modules = [ "First Aid", ".offline-science" ].map.with_index do |name, index|
      LibraryModule.create!(name: "Selected module #{index}", folder_name: name, icon: @asset, user: @user)
    end
    LibraryModule.create!(name: "Unselected module", folder_name: "unselected", icon: @asset, user: @user)
    @library.selected_modules = modules
    build = run_export(request_export)
    storage = LibraryBuilds::Storage.new(build)
    module_root = storage.folder_path.join("modules")
    assert_equal [ ".offline-science", "First Aid" ], module_root.children.map { |path| path.basename.to_s }.sort
    module_root.children.each { |path| assert_empty path.children }
    Zip::File.open(storage.archive_path) do |zip|
      entries = zip.entries.select { |entry| entry.name.start_with?("export/modules/") }
      assert_equal [ "export/modules/", "export/modules/.offline-science/", "export/modules/First Aid/" ], entries.map(&:name).sort
      entries.each { |entry| assert_predicate entry, :directory? }
    end

    @library.selected_modules = [ modules.last ]
    run_export(request_export)
    storage = LibraryBuilds::Storage.new(build.reload)
    assert_equal [ ".offline-science" ], storage.folder_path.join("modules").children.map { |path| path.basename.to_s }
    Zip::File.open(storage.archive_path) do |zip|
      assert_nil zip.find_entry("export/modules/First Aid/")
      assert_predicate zip.find_entry("export/modules/.offline-science/"), :directory?
    end

    @library.selected_modules.clear
    run_export(request_export)
    storage = LibraryBuilds::Storage.new(build.reload)
    refute storage.folder_path.join("modules").exist?
    Zip::File.open(storage.archive_path) do |zip|
      assert_empty zip.entries.select { |entry| entry.name.start_with?("export/modules/") }
    end
  end

  test "unsafe module folder names fail without replacing a published export" do
    build = run_export(request_export)
    archive = LibraryBuilds::Storage.new(build).archive_path.binread
    mod = LibraryModule.create!(name: "Unsafe module", folder_name: "../escape", icon: @asset, user: @user)
    @library.selected_modules << mod

    [ "../escape", "/absolute", "nested/folder", "nested\\folder", ".", ".." ].each do |name|
      mod.update!(folder_name: name)
      build = request_export
      error = assert_raises(LibraryBuilds::Error) { run_export(build) }
      assert_includes error.message, "must be a single folder name"
      assert_predicate build.reload, :failed?
      assert_empty build.working_files
      assert_equal 1, build.published_generation
      assert_equal archive, LibraryBuilds::Storage.new(build).archive_path.binread
    end
  end

  test "selected modules with duplicate folder names fail instead of merging folders" do
    2.times do |index|
      @library.selected_modules << LibraryModule.create!(name: "Module #{index}", folder_name: "same-folder", icon: @asset, user: @user)
    end
    build = request_export
    error = assert_raises(LibraryBuilds::Error) { run_export(build) }
    assert_includes error.message, "distinct folder names"
    assert_predicate build.reload, :failed?
    refute_predicate build, :published?
    assert_empty build.working_files
  end

  test "rebuild replaces the sole output and reads changed metadata" do
    type = MetadataType.create!(name: "Changing Type", user: @user)
    value = type.metadata.create!(name: "FirstValue", user: @user)
    @content.metadata << value
    build = run_export(request_export)
    old_path = LibraryBuilds::Storage.new(build).generation_path(1)
    value.update!(name: "SecondValue")
    type.update!(name: "Renamed Type")
    run_export(request_export)
    refute old_path.exist?
    assert_equal 1, LibraryBuild.where(library_version: @version).count
    assert_equal [ "generation-2" ], LibraryBuilds::Storage.new(build).root.children.select(&:directory?).map { |path| path.basename.to_s }
    export_db(build.reload) do |db|
      assert_equal "Renamed Type", db.get_first_value("SELECT type_name FROM metadata_type")
      assert_equal [ [ @content.id ] ], db.execute("SELECT rowid FROM content_fts WHERE content_fts MATCH 'SecondValue'")
      assert_empty db.execute("SELECT rowid FROM content_fts WHERE content_fts MATCH 'FirstValue'")
    end
    type.destroy!
    run_export(request_export)
    export_db(build.reload) do |db|
      assert_equal 0, db.get_first_value("SELECT count(*) FROM metadata_type")
      assert_equal 0, db.get_first_value("SELECT count(*) FROM content_metadata")
    end
  end

  test "failed regeneration retains the previous output and releases working files" do
    build = run_export(request_export)
    archive = LibraryBuilds::Storage.new(build).archive_path.read
    build = request_export
    @content.file.blob.service.delete(@content.file.blob.key)
    assert_raises(ActiveStorage::FileNotFoundError) { run_export(build) }
    assert_predicate build.reload, :failed?
    assert_equal 1, build.published_generation
    assert_equal archive, LibraryBuilds::Storage.new(build).archive_path.read
    assert_empty build.working_files
    assert_equal 1, LibraryBuilds::Storage.new(build).root.children.count(&:directory?)
  end

  test "corrupt copies fail validation and clean all incomplete files" do
    build = request_export
    @content.file.blob.service.upload(@content.file.blob.key, StringIO.new("bad bytes"))
    assert_raises(ActiveStorage::IntegrityError) { run_export(build) }
    assert_predicate build.reload, :failed?
    refute_predicate build, :published?
    assert_empty build.working_files
    assert_empty LibraryBuilds::Storage.new(build).root.children.select(&:directory?)
  end

  test "exports audio and video once each and handles empty libraries" do
    # Add placements before locking a fresh version.
    [ [ ".mp3", "audio/mpeg" ], [ ".mp4", "video/mp4" ] ].each do |extension, content_type|
      content = build_export_content(extension:, content_type:)
      folder = @library.current_version.library_folders.find_by!(name: @root.name)
      LibraryFolderContent.create!(library_folder: folder, content:)
    end
    source_version = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "3.0", user: @user)
    build = run_export(request_export(source_version))
    assert_equal %w[.mp3 .mp4 .pdf], LibraryBuilds::Storage.new(build).folder_path.join("content").children.map(&:extname).sort
    refute LibraryBuilds::Storage.new(build).folder_path.join("modules").exist?
    Zip::File.open(LibraryBuilds::Storage.new(build).archive_path) do |zip|
      assert_empty zip.entries.select { |entry| entry.name.start_with?("export/modules/") }
    end

    empty = Library.create!(name: "Empty", user: @user)
    empty_version = empty.current_version
    LibraryVersions::Create.call(library: empty, version_number: "2.0", user: @user)
    empty_build = run_export(request_export(empty_version))
    export_db(empty_build) { |db| assert_equal 0, db.get_first_value("SELECT count(*) FROM content") }
    assert_empty LibraryBuilds::Storage.new(empty_build).folder_path.join("content").children
    assert_empty LibraryBuilds::Storage.new(empty_build).folder_path.join("assets").children
    refute LibraryBuilds::Storage.new(empty_build).folder_path.join("modules").exist?
  end

  test "obsolete generations and duplicate workers do not replace outputs" do
    build = run_export(request_export)
    archive = LibraryBuilds::Storage.new(build).archive_path.read
    assert_equal false, LibraryBuilds::Export.call(build:, generation: 1)
    request_export
    assert_equal false, LibraryBuilds::Export.call(build:, generation: 1)
    storage = LibraryBuilds::Storage.new(build)
    storage.with_lock do
      assert_equal false, LibraryBuilds::Export.call(build:, generation: 2)
    end
    assert_equal archive, storage.archive_path.read
  end
end
