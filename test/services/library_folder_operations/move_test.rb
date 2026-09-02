require "test_helper"

class LibraryFolderOperations::MoveTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @source = create_folder!("Source")
    @destination = create_folder!("Destination")
    @selected = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected)
    @source_placement = LibraryFolderContent.create!(library_folder: @source, content: contents(:one))
  end

  test "moves direct content and top-level folders while descendants follow" do
    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: @source.id,
      folder_ids: [ @selected.id ],
      content_ids: [ contents(:one).id ],
      destination_folder_id: @destination.id
    )

    assert_equal @destination, @selected.reload.parent_folder
    assert_equal @selected, @nested.reload.parent_folder
    refute @source.library_folder_contents.exists?(content_id: contents(:one).id)
    assert @destination.library_folder_contents.exists?(content_id: contents(:one).id)
    assert_equal @library.current_version_id,
      @destination.library_folder_contents.find_by!(content: contents(:one)).library_version_id
    assert @library.current_version.library_version_contents.exists?(content: contents(:one))
  end

  test "moving content merges an existing destination placement" do
    destination_placement = LibraryFolderContent.create!(
      library_folder: @destination,
      content: contents(:one)
    )

    assert_difference("LibraryFolderContent.count", -1) do
      LibraryFolderOperations::Move.call(
        library: @library,
        source_folder_id: @source.id,
        folder_ids: [],
        content_ids: [ contents(:one).id ],
        destination_folder_id: @destination.id
      )
    end

    assert LibraryFolderContent.exists?(destination_placement.id)
    refute LibraryFolderContent.exists?(@source_placement.id)
  end

  test "moving a root under another folder clears its root logo" do
    root = create_folder!("Root to move")

    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ root.id ],
      content_ids: [],
      destination_folder_id: @destination.id
    )

    assert_equal @destination, root.reload.parent_folder
    assert_nil root.logo
  end

  test "rejects the source parent and selected subtree as destinations" do
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      LibraryFolderOperations::Move.call(
        library: @library,
        source_folder_id: @source.id,
        folder_ids: [ @selected.id ],
        content_ids: [],
        destination_folder_id: @source.id
      )
    end
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      LibraryFolderOperations::Move.call(
        library: @library,
        source_folder_id: @source.id,
        folder_ids: [ @selected.id ],
        content_ids: [],
        destination_folder_id: @nested.id
      )
    end

    assert_equal @source, @selected.reload.parent_folder
  end

  test "rejects moves when the current version is locked" do
    @library.current_version.update_column(:locked_at, Time.current)

    assert_no_difference("LibraryFolderContent.count") do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::Move.call(
          library: @library,
          source_folder_id: @source.id,
          folder_ids: [ @selected.id ],
          content_ids: [ contents(:one).id ],
          destination_folder_id: @destination.id
        )
      end
    end

    assert_equal @source, @selected.reload.parent_folder
    assert LibraryFolderContent.exists?(@source_placement.id)
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
