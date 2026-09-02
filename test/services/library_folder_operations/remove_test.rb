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

  test "removes direct placements and recursive folder trees without deleting content" do
    assert_no_difference("Content.count") do
      LibraryFolderOperations::Remove.call(
        library: @library,
        source_folder_id: @source.id,
        folder_ids: [ @selected.id ],
        content_ids: [ contents(:one).id ]
      )
    end

    refute LibraryFolderContent.exists?(@direct_placement.id)
    refute LibraryFolderContent.exists?(@nested_placement.id)
    refute LibraryFolder.exists?(@selected.id)
    refute LibraryFolder.exists?(@nested.id)
    assert LibraryFolder.exists?(@source.id)
    assert LibraryFolder.exists?(@sibling.id)
    assert LibraryFolderContent.exists?(@outside_placement.id)
    assert Content.exists?(contents(:one).id)
    assert Content.exists?(contents(:two).id)
    refute @library.current_version.library_version_contents.exists?(content: contents(:one))
    assert @library.current_version.library_version_contents.exists?(content: contents(:two))
  end

  test "rejects removal when the current version is locked" do
    @library.current_version.update_column(:locked_at, Time.current)

    assert_no_difference([ "LibraryFolder.count", "LibraryFolderContent.count" ]) do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::Remove.call(
          library: @library,
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
