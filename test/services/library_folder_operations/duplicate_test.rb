require "test_helper"

class LibraryFolderOperations::DuplicateTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @source = create_folder!("Source")
    @destination = create_folder!("Destination")
    @selected = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected)
    LibraryFolderContent.create!(library_folder: @source, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @nested, content: contents(:two))
  end

  test "copies placements and recursive folder structure without changing originals" do
    assert_difference("LibraryFolder.count", 2) do
      assert_difference("LibraryFolderContent.count", 2) do
        LibraryFolderOperations::Duplicate.call(
          library: @library,
          source_folder_id: @source.id,
          folder_ids: [ @selected.id ],
          content_ids: [ contents(:one).id ],
          destination_folder_id: @destination.id,
          user: users(:one)
        )
      end
    end

    copied_selected = @destination.child_folders.find_by!(name: @selected.name)
    copied_nested = copied_selected.child_folders.find_by!(name: @nested.name)
    assert_equal @library.current_version, copied_selected.library_version
    assert_equal @library.current_version, copied_nested.library_version
    assert_equal [ contents(:two) ], copied_nested.contents.to_a
    assert_equal [ contents(:one) ], @destination.contents.to_a
    assert @library.current_version.library_version_contents.exists?(content: contents(:one))
    assert @library.current_version.library_version_contents.exists?(content: contents(:two))
    assert copied_nested.library_folder_contents.all? { |placement|
      placement.library_version_id == @library.current_version_id
    }
    assert_equal @source, @selected.reload.parent_folder
    assert_equal @selected, @nested.reload.parent_folder
  end

  test "skips an existing direct destination placement" do
    LibraryFolderContent.create!(library_folder: @destination, content: contents(:one))

    assert_no_difference("LibraryFolderContent.count") do
      LibraryFolderOperations::Duplicate.call(
        library: @library,
        source_folder_id: @source.id,
        folder_ids: [],
        content_ids: [ contents(:one).id ],
        destination_folder_id: @destination.id,
        user: users(:one)
      )
    end
  end

  test "copies a root as a child without its root logo" do
    root = create_folder!("Root to copy")

    LibraryFolderOperations::Duplicate.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ root.id ],
      content_ids: [],
      destination_folder_id: @destination.id,
      user: users(:one)
    )

    copy = @destination.child_folders.find_by!(name: root.name)
    assert_nil copy.logo
    assert root.reload.logo
  end

  test "rejects a destination inside the selected tree" do
    assert_no_difference("LibraryFolder.count") do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::Duplicate.call(
          library: @library,
          source_folder_id: @source.id,
          folder_ids: [ @selected.id ],
          content_ids: [],
          destination_folder_id: @nested.id,
          user: users(:one)
        )
      end
    end
  end

  test "rejects duplication when the current version is locked" do
    @library.current_version.update_column(:locked_at, Time.current)

    assert_no_difference([ "LibraryFolder.count", "LibraryFolderContent.count" ]) do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::Duplicate.call(
          library: @library,
          source_folder_id: @source.id,
          folder_ids: [ @selected.id ],
          content_ids: [],
          destination_folder_id: @destination.id,
          user: users(:one)
        )
      end
    end
  end

  private

  def create_folder!(name, parent_folder: nil)
    @library.current_version.library_folders.create!(
      library: @library,
      name:,
      parent_folder:,
      user: users(:one),
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end
end
