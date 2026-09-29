require "test_helper"

class LibraryFolderOperations::SelectionTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @source = create_folder!("Source")
    @selected = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected)
    @sibling = create_folder!("Sibling", parent_folder: @source)
    @direct_placement = LibraryFolderContent.create!(library_folder: @source, content: contents(:one))
    @nested_placement = LibraryFolderContent.create!(library_folder: @nested, content: contents(:two))
  end

  test "resolves direct selections and builds a complete recursive tree" do
    selection = build_selection(folder_ids: [ @selected.id ], content_ids: [ contents(:one).id ])

    assert_equal @source, selection.source_folder
    assert_equal @library.current_version, selection.library_version
    assert_equal @library.current_version.library_folders.order(:name, :id).to_a,
      selection.all_folders
    assert_equal [ @selected ], selection.selected_folders
    assert_equal [ @direct_placement ], selection.direct_content_placements
    assert_equal [ @selected, @nested ], selection.subtree_folders
    assert_equal Set[@selected.id, @nested.id], selection.blocked_folder_ids
    assert_equal [ @nested_placement ], selection.subtree_content_placements

    root_node = selection.removal_tree.first
    assert_equal @selected, root_node.folder
    assert_empty root_node.contents
    assert_equal @nested, root_node.children.first.folder
    assert_equal [ contents(:two) ], root_node.children.first.contents
  end

  test "rejects empty malformed indirect and stale selections" do
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      build_selection(folder_ids: [], content_ids: [])
    end
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      build_selection(folder_ids: [ "bad" ], content_ids: [])
    end
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      build_selection(folder_ids: [ @nested.id ], content_ids: [])
    end
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      build_selection(folder_ids: [], content_ids: [ contents(:two).id ])
    end
    assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
      build_selection(folder_ids: [ 999_999 ], content_ids: [])
    end
  end

  test "rejects folders from another library as not found" do
    other_library = Library.create!(name: "Other", user: users(:one))
    foreign_folder = create_folder!("Foreign", library: other_library)

    assert_raises(ActiveRecord::RecordNotFound) do
      build_selection(folder_ids: [ foreign_folder.id ], content_ids: [])
    end
  end

  private

  def build_selection(folder_ids:, content_ids:)
    LibraryFolderOperations::Selection.new(
      library: @library,
      source_folder_id: @source.id,
      folder_ids:,
      content_ids:
    )
  end

  def create_folder!(name, library: @library, parent_folder: nil)
    library.current_version.library_folders.create!(
      library:,
      name:,
      parent_folder:,
      user: users(:one),
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end
end
