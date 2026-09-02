require "test_helper"

class LibrarySnapshotConstraintsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @library = Library.create!(name: "Health Library", user: @user)
    @version = @library.current_version
    @root = @version.library_folders.create!(
      library: @library,
      name: "Guides",
      user: @user,
      logo: library_assets(:one)
    )
    @child = @version.library_folders.create!(
      library: @library,
      name: "First aid",
      parent_folder: @root,
      user: @user
    )
    @placement = LibraryFolderContent.create!(
      library_folder: @child,
      content: contents(:one)
    )
  end

  test "database allows only one unlocked version per library" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      LibraryVersion.transaction(requires_new: true) do
        @library.library_versions.create!(version_number: "2.0", user: @user)
      end
    end
  end

  test "database rejects a parent from another version" do
    current_version = LibraryVersions::Create.call(
      library: @library,
      version_number: "2.0",
      user: @user
    )
    current_child = current_version.library_folders.find_by!(name: @child.name)

    assert_raises(ActiveRecord::InvalidForeignKey) do
      LibraryFolder.transaction(requires_new: true) do
        current_child.update_columns(parent_folder_id: @root.id)
      end
    end
  end

  test "database rejects a placement whose folder belongs to another version" do
    current_version = LibraryVersions::Create.call(
      library: @library,
      version_number: "2.0",
      user: @user
    )
    current_only_folder = current_version.library_folders.create!(
      library: @library,
      name: "Current only",
      user: @user,
      logo: library_assets(:one)
    )

    assert_raises(ActiveRecord::InvalidForeignKey) do
      LibraryFolderContent.transaction(requires_new: true) do
        @placement.update_columns(library_folder_id: current_only_folder.id)
      end
    end
  end

  test "database requires a matching content manifest for every placement" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      LibraryFolderContent.transaction(requires_new: true) do
        LibraryFolderContent.insert_all!([ {
          library_folder_id: @child.id,
          library_version_id: @version.id,
          content_id: contents(:two).id
        } ])
      end
    end
  end

  test "database rejects duplicate content manifests" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      LibraryVersionContent.transaction(requires_new: true) do
        LibraryVersionContent.insert_all!([ {
          library_version_id: @version.id,
          content_id: @placement.content_id,
          file_checksum: "duplicate"
        } ])
      end
    end
  end
end
