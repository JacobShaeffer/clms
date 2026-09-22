require "test_helper"

class LibraryFolderOperations::RemoveTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @source = create_folder!("Source")
    @selected = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected)
    @sibling = create_folder!("Sibling", parent_folder: @source)
    @direct_placement = LibraryFolderContent.create!(library_folder: @source, content: contents(:one))
    @nested_placement = LibraryFolderContent.create!(library_folder: @nested, content: contents(:two))
    @outside_placement = LibraryFolderContent.create!(library_folder: @sibling, content: contents(:two))
  end

  test "marks direct placements and recursive folder trees for removal without deleting content" do
    assert_no_difference("Content.count") do
      LibraryFolderOperations::Remove.call(
        library: @library,
        user: users(:one),
        source_folder_id: @source.id,
        folder_ids: [ @selected.id ],
        content_ids: [ contents(:one).id ]
      )
    end

    assert_predicate @direct_placement.reload, :pending_removal?
    assert_predicate @nested_placement.reload, :pending_removal?
    assert_predicate @selected.reload, :pending_removal?
    assert_predicate @nested.reload, :pending_removal?
    assert LibraryFolder.exists?(@source.id)
    assert LibraryFolder.exists?(@sibling.id)
    assert LibraryFolderContent.exists?(@outside_placement.id)
    assert Content.exists?(contents(:one).id)
    assert Content.exists?(contents(:two).id)
    assert @library.current_version.library_version_contents.exists?(content: contents(:one))
    assert @library.current_version.library_version_contents.exists?(content: contents(:two))
    assert_equal 2, @library.current_version.library_changes.remove_content.or(
      @library.current_version.library_changes.remove_folder
    ).count
  end

  test "rejects removal when the current version is locked" do
    @library.current_version.update_column(:locked_at, Time.current)

    assert_no_difference([ "LibraryFolder.count", "LibraryFolderContent.count" ]) do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::Remove.call(
          library: @library,
          user: users(:one),
          source_folder_id: @source.id,
          folder_ids: [ @selected.id ],
          content_ids: [ contents(:one).id ]
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
