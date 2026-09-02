require "test_helper"

class LibraryVersions::CreateTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @version = @library.current_version
    @root = create_folder!("Guides")
    @child = create_folder!("First Aid", parent_folder: @root)
    @content = create_content_with_file!("original file")
    LibraryFolderContent.create!(library_folder: @root, content: @content)
    LibraryFolderContent.create!(library_folder: @child, content: @content)
  end

  test "atomically locks the previous version and clones its complete snapshot" do
    new_version = LibraryVersions::Create.call(
      library: @library,
      version_number: " 2.0 ",
      user: users(:two)
    )

    assert_equal "2.0", new_version.version_number
    assert_equal @version, new_version.previous_version
    assert_equal new_version, @library.reload.current_version
    assert_predicate @version.reload, :locked?
    assert_predicate new_version, :editable?
    assert_equal 1, @library.library_versions.where(locked_at: nil).count

    cloned_root = new_version.library_folders.find_by!(name: @root.name)
    cloned_child = new_version.library_folders.find_by!(name: @child.name)
    refute_equal @root.id, cloned_root.id
    refute_equal @child.id, cloned_child.id
    assert_equal cloned_root, cloned_child.parent_folder
    assert_equal @root.logo, cloned_root.logo
    assert_equal @root.user, cloned_root.user
    assert_equal 2, new_version.library_folder_contents.where(content: @content).count
    assert_equal 1, new_version.library_version_contents.where(content: @content).count
    assert_equal @content.file.blob.checksum,
      new_version.library_version_contents.find_by!(content: @content).file_checksum
  end

  test "changes to the cloned version do not affect the locked snapshot" do
    new_version = LibraryVersions::Create.call(
      library: @library,
      version_number: "2.0",
      user: users(:one)
    )
    cloned_child = new_version.library_folders.find_by!(name: @child.name)

    cloned_child.update!(name: "Updated First Aid")
    cloned_child.library_folder_contents.find_by!(content: @content).destroy!

    assert_equal "First Aid", @child.reload.name
    assert @child.library_folder_contents.exists?(content: @content)
    assert @version.library_version_contents.exists?(content: @content)
  end

  test "file change history is frozen when the next version is created" do
    second_version = LibraryVersions::Create.call(
      library: @library,
      version_number: "2.0",
      user: users(:one)
    )
    assert_empty second_version.file_changed_content_ids

    replace_file!(@content, "second file")
    assert_equal [ @content.id ], second_version.file_changed_content_ids

    third_version = LibraryVersions::Create.call(
      library: @library,
      version_number: "3.0",
      user: users(:one)
    )
    assert_equal [ @content.id ], second_version.reload.file_changed_content_ids
    assert_empty third_version.file_changed_content_ids

    replace_file!(@content, "third file")
    assert_equal [ @content.id ], third_version.file_changed_content_ids
    assert_equal [ @content.id ], second_version.file_changed_content_ids
  end

  test "invalid creation leaves the current version editable" do
    assert_raises(ActiveRecord::RecordInvalid) do
      LibraryVersions::Create.call(
        library: @library,
        version_number: "1.0",
        user: users(:one)
      )
    end

    assert_equal @version, @library.reload.current_version
    assert_predicate @version.reload, :editable?
    assert_equal 1, @library.library_versions.count
  end

  private

  def create_folder!(name, parent_folder: nil)
    @version.library_folders.create!(
      library: @library,
      name:,
      parent_folder:,
      user: users(:one),
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end

  def create_content_with_file!(bytes)
    Content.new(
      title: "Version content #{SecureRandom.hex(4)}",
      display_title: "Version content",
      description: "Content for a library snapshot.",
      user: users(:one)
    ).tap do |content|
      content.file.attach(
        io: StringIO.new(bytes),
        filename: "version-content-#{SecureRandom.hex(4)}.png",
        content_type: "image/png"
      )
      content.save!
    end
  end

  def replace_file!(content, bytes)
    content.file.attach(
      io: StringIO.new(bytes),
      filename: "version-content-#{SecureRandom.hex(4)}.png",
      content_type: "image/png"
    )
  end
end
