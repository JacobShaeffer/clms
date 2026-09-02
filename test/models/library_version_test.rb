require "test_helper"

class LibraryVersionTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
  end

  test "creation service links the previous version locks it and promotes an editable successor" do
    previous_version = @library.current_version

    version = LibraryVersions::Create.call(
      library: @library,
      version_number: " 2.0 ",
      user: users(:two)
    )

    assert_equal "2.0", version.version_number
    assert_equal previous_version, version.previous_version
    assert_equal version, previous_version.reload.next_version
    assert_equal version, @library.reload.current_version
    assert_predicate previous_version, :locked?
    assert_predicate version, :editable?
  end

  test "version number is unique within a library" do
    duplicate = @library.library_versions.build(
      version_number: "1.0",
      user: users(:one)
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version_number], "has already been taken"
  end

  test "the same version number can be used by different libraries" do
    other_library = Library.create!(name: "Science Library", user: users(:one))

    assert_equal "1.0", @library.current_version.version_number
    assert_equal "1.0", other_library.current_version.version_number
  end

  test "previous version must belong to the same library" do
    other_library = Library.create!(name: "Science Library", user: users(:one))
    version = @library.current_version
    version.previous_version = other_library.current_version

    assert_not version.valid?
    assert_includes version.errors[:previous_version], "must belong to this library"
  end

  test "a locked version cannot be changed or deleted" do
    version = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: users(:one))

    assert_not version.reload.update(version_number: "renamed")
    assert_includes version.errors[:base], "Locked library versions cannot be changed"
    assert_not version.destroy
    assert_includes version.errors[:base], "Locked library versions cannot be deleted"
  end
end
