require "test_helper"

class LibraryVersionContentTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @version = @library.current_version
    @folder = @version.library_folders.create!(
      library: @library,
      name: "Guides",
      user: users(:one),
      logo: library_assets(:one)
    )
    LibraryFolderContent.create!(library_folder: @folder, content: contents(:one))
    @manifest = @version.library_version_contents.find_by!(content: contents(:one))
  end

  test "content is unique within a version" do
    duplicate = @version.library_version_contents.build(content: contents(:one))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:content_id], "has already been taken"
  end

  test "a locked manifest cannot be changed or destroyed" do
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: users(:one))

    assert_not @manifest.reload.update(file_checksum: "changed")
    assert_includes @manifest.errors[:base], "Locked library versions cannot be changed"
    assert_not @manifest.destroy
    assert_includes @manifest.errors[:base], "Locked library versions cannot be changed"

    new_manifest = @version.library_version_contents.build(content: contents(:two))
    assert_not new_manifest.valid?
    assert_includes new_manifest.errors[:base], "Locked library versions cannot be changed"
  end
end
