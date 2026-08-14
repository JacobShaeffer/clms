require "test_helper"

class LibraryFolderTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @other_library = Library.create!(name: "Science Library", user: users(:one))
    @logo = library_assets(:one)
  end

  test "roots returns only folders without a parent" do
    root = create_folder!(name: "Health")
    create_folder!(name: "First Aid", parent_folder: root)

    assert_equal [ root ], @library.library_folders.roots.to_a
  end

  test "parent folder must belong to the same library" do
    other_root = @other_library.library_folders.create!(
      name: "Science",
      user: users(:one),
      logo: @logo
    )
    folder = @library.library_folders.build(
      name: "Invalid child",
      parent_folder: other_root,
      user: users(:one),
      logo: @logo
    )

    assert_not folder.valid?
    assert_includes folder.errors[:parent_folder], "must belong to this library"
  end

  test "folder cannot be its own parent" do
    folder = create_folder!(name: "Health")
    folder.parent_folder = folder

    assert_not folder.valid?
    assert_includes folder.errors[:parent_folder], "cannot be itself"
  end

  test "folder cannot use one of its descendants as its parent" do
    root = create_folder!(name: "Health")
    child = create_folder!(name: "First Aid", parent_folder: root)
    root.parent_folder = child

    assert_not root.valid?
    assert_includes root.errors[:parent_folder], "cannot be a descendant"
  end

  private

  def create_folder!(name:, parent_folder: nil)
    @library.library_folders.create!(
      name: name,
      parent_folder: parent_folder,
      user: users(:one),
      logo: @logo
    )
  end
end
