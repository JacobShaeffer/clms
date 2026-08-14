require "test_helper"

class LibraryFolderContentTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @first_folder = create_folder!("First")
    @second_folder = create_folder!("Second")
  end

  test "a content item can be placed once per folder and in multiple folders" do
    first_placement = LibraryFolderContent.create!(
      library_folder: @first_folder,
      content: contents(:one)
    )
    second_placement = LibraryFolderContent.create!(
      library_folder: @second_folder,
      content: contents(:one)
    )
    duplicate = LibraryFolderContent.new(
      library_folder: @first_folder,
      content: contents(:one)
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:content_id], "has already been taken"
    assert_equal [ first_placement, second_placement ], contents(:one).library_folder_contents.order(:id).to_a
    assert_equal [ contents(:one) ], @library.contents.distinct.to_a
  end

  test "destroying content removes placements" do
    placement = LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))

    contents(:one).destroy!

    refute LibraryFolderContent.exists?(placement.id)
  end

  test "a folder with content cannot be destroyed" do
    LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))

    assert_not @first_folder.destroy
    assert_includes @first_folder.errors[:base], "Cannot delete record because dependent library folder contents exist"
  end

  private

  def create_folder!(name)
    @library.library_folders.create!(
      name:,
      user: users(:one),
      logo: library_assets(:one)
    )
  end
end
