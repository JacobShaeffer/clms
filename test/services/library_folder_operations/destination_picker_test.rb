require "test_helper"

class LibraryFolderOperations::DestinationPickerTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @source = create_folder!("Source")
    @selected = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected)
    @destination = create_folder!("Destination")
    @selection = LibraryFolderOperations::Selection.new(
      library: @library,
      source_folder_id: @source.id,
      folder_ids: [ @selected.id ],
      content_ids: []
    )
  end

  test "shows direct folders and blocks selected trees" do
    picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: :move
    )

    assert_equal [ @destination, @source ], picker.folders
    assert picker.selectable?(@destination)
    refute picker.selectable?(@source)
    assert picker.openable?(@source)

    source_picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: :duplicate,
      current_folder_id: @source.id
    )
    refute source_picker.selectable?(@selected)
    refute source_picker.openable?(@selected)
  end

  test "uses a valid current folder as the destination" do
    picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: :duplicate,
      current_folder_id: @destination.id
    )

    assert picker.current_folder_selectable?
  end

  test "does not use the library root or existing source parent as a move destination" do
    root_picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: :move
    )
    source_picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: :move,
      current_folder_id: @source.id
    )

    refute root_picker.current_folder_selectable?
    refute source_picker.current_folder_selectable?
  end

  test "rejects opening a selected subtree" do
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      LibraryFolderOperations::DestinationPicker.new(
        library: @library,
        selection: @selection,
        operation: :move,
        current_folder_id: @nested.id
      )
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
