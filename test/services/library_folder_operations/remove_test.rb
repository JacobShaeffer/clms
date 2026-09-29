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

  test "immediately deletes direct placements and recursive folder trees without deleting content" do
    selected_id = @selected.id
    nested_id = @nested.id
    direct_placement_id = @direct_placement.id
    nested_placement_id = @nested_placement.id

    assert_no_difference("Content.count") do
      LibraryFolderOperations::Remove.call(
        library: @library,
        user: users(:one),
        source_folder_id: @source.id,
        folder_ids: [ @selected.id ],
        content_ids: [ contents(:one).id ]
      )
    end

    refute LibraryFolderContent.exists?(direct_placement_id)
    refute LibraryFolderContent.exists?(nested_placement_id)
    refute LibraryFolder.exists?(selected_id)
    refute LibraryFolder.exists?(nested_id)
    assert LibraryFolder.exists?(@source.id)
    assert LibraryFolder.exists?(@sibling.id)
    assert LibraryFolderContent.exists?(@outside_placement.id)
    assert Content.exists?(contents(:one).id)
    assert Content.exists?(contents(:two).id)
    refute @library.current_version.library_version_contents.exists?(content: contents(:one))
    assert @library.current_version.library_version_contents.exists?(content: contents(:two))
    assert_equal 2, @library.current_version.library_changes.remove_content.or(
      @library.current_version.library_changes.remove_folder
    ).count

    content_change = @library.current_version.library_changes.remove_content.last
    folder_change = @library.current_version.library_changes.remove_folder.last
    assert_equal direct_placement_id,
      content_change.details.fetch("placement_snapshot").fetch("id")
    assert_equal [ selected_id, nested_id ],
      folder_change.details.fetch("folder_snapshots").pluck("id")
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
