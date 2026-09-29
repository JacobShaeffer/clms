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

  test "content cannot be destroyed while a version references it" do
    placement = LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))

    assert_not contents(:one).destroy

    assert LibraryFolderContent.exists?(placement.id)
    assert_includes contents(:one).errors[:base],
      "Cannot delete record because dependent library folder contents exist"
  end

  test "placements share one manifest per version and remove it after the last placement" do
    first_placement = LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))
    second_placement = LibraryFolderContent.create!(library_folder: @second_folder, content: contents(:one))

    assert_equal 1, @library.current_version.library_version_contents.where(content: contents(:one)).count

    first_placement.destroy!
    assert @library.current_version.library_version_contents.exists?(content: contents(:one))

    second_placement.destroy!
    refute @library.current_version.library_version_contents.exists?(content: contents(:one))
  end

  test "a placement cannot be reassigned" do
    placement = LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))

    placement.content = contents(:two)
    assert_not placement.save
    assert_includes placement.errors[:base], "Content placements cannot be reassigned"

    placement.reload.library_folder = @second_folder
    assert_not placement.save
    assert_includes placement.errors[:base], "Content placements cannot be reassigned"
  end

  test "placements in locked versions cannot be created changed or destroyed" do
    placement = LibraryFolderContent.create!(library_folder: @first_folder, content: contents(:one))
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: users(:one))

    assert_not placement.reload.update(content: contents(:two))
    assert_includes placement.errors[:base], "Locked library versions cannot be changed"
    assert_not placement.destroy
    assert_includes placement.errors[:base], "Locked library versions cannot be changed"

    new_placement = @first_folder.library_folder_contents.build(content: contents(:two))
    assert_not new_placement.valid?
    assert_includes new_placement.errors[:base], "Locked library versions cannot be changed"
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
