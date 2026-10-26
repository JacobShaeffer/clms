require "tmpdir"

module LibraryBuildHelpers
  def setup_build_library
    @previous_export_root = Rails.configuration.x.library_exports_root
    @export_root = Dir.mktmpdir("library-export-test-")
    Rails.configuration.x.library_exports_root = @export_root
    @user = users(:one)
    @user.update!(role: :admin)
    @asset = library_assets(:one)
    @asset.image.attach(io: StringIO.new("PNG export bytes"), filename: "logo.png", content_type: "image/png")
    @library = Library.create!(name: "Export Library", user: @user)
    @version = @library.current_version
    @root = @version.library_folders.create!(name: "Saved Subject", user: @user, logo: @asset)
    @child = @version.library_folders.create!(name: "Saved Child", user: @user, parent_folder: @root)
    @content = build_export_content
    [ @root, @child ].each { |folder| LibraryFolderContent.create!(library_folder: folder, content: @content) }
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)
    @version.reload
  end

  def teardown_build_library
    Rails.configuration.x.library_exports_root = @previous_export_root
    FileUtils.remove_entry(@export_root) if @export_root && File.exist?(@export_root)
  end

  def build_export_content(extension: ".pdf", content_type: "application/pdf", bytes: nil)
    token = SecureRandom.hex(6)
    Content.new(user: @user, title: "Catalog #{token}", display_title: "Display #{token}",
      description: "Searchable description #{token}", year_of_publication: 2024, additional_notes: 3).tap do |content|
      content.file.attach(io: StringIO.new(bytes || "document #{token}"), filename: "document-#{token}#{extension}", content_type:)
      content.save!
    end
  end

  def request_export(version = @version)
    LibraryBuilds::Request.call(library_version: version, user: @user)
  end

  def run_export(build)
    LibraryBuilds::Export.call(build:, generation: build.generation)
    build.reload
  end

  def export_db(build)
    SQLite3::Database.open(LibraryBuilds::Storage.new(build).folder_path.join("library.db").to_s) do |db|
      yield db
    end
  end
end
