require "test_helper"

class LibraryTest < ActiveSupport::TestCase
  test "creating a library creates version 1.0 and makes it current" do
    library = Library.create!(name: "Health Library", user: users(:one))

    assert_equal 1, library.library_versions.count

    initial_version = library.library_versions.first
    assert_equal "1.0", initial_version.version_number
    assert_equal users(:one), initial_version.user
    assert_nil initial_version.previous_version
    assert_equal initial_version, library.reload.current_version
  end

  test "current version must belong to the library" do
    library = Library.create!(name: "Health Library", user: users(:one))
    other_library = Library.create!(name: "Science Library", user: users(:one))

    library.current_version = other_library.current_version

    assert_not library.valid?
    assert_includes library.errors[:current_version], "must belong to this library"
  end

  test "name is required" do
    library = Library.new(name: "", user: users(:one))

    assert_not library.valid?
    assert_includes library.errors[:name], "can't be blank"
  end
end
