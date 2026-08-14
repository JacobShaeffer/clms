require "test_helper"

class LibraryFolderPathIndexTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @root = create_folder!("Guides")
    @child = create_folder!("First Aid", parent_folder: @root)
    @index = LibraryFolderPathIndex.new(library: @library)
  end

  test "returns root-to-folder paths and complete breadcrumbs" do
    assert_equal [ @root, @child ], @index.path(@child)
    assert_equal "Health Library / Guides / First Aid", @index.breadcrumb(@child)
  end

  test "rejects folders from another library" do
    other_library = Library.create!(name: "Other Library", user: users(:one))
    other_folder = other_library.library_folders.create!(
      name: "Other",
      user: users(:one),
      logo: library_assets(:one)
    )

    assert_raises(LibraryFolderPathIndex::InvalidFolder) { @index.path(other_folder) }
  end

  private

  def create_folder!(name, parent_folder: nil)
    @library.library_folders.create!(
      name:,
      parent_folder:,
      user: users(:one),
      logo: library_assets(:one)
    )
  end
end
