require "test_helper"

class LibraryBuildTest < ActiveSupport::TestCase
  test "requires a locked version and allows only one build per version" do
    user = users(:one)
    library = Library.create!(name: "Build validation", user:)
    version = library.current_version
    build = LibraryBuild.new(library_version: version, user:, requested_at: Time.current)
    refute build.valid?
    assert_includes build.errors[:library_version], "must be locked"
    LibraryVersions::Create.call(library:, version_number: "2.0", user:)
    build.library_version.reload
    build.save!
    copy = LibraryBuild.new(library_version: version, user:, requested_at: Time.current)
    refute copy.valid?
    assert_includes copy.errors[:library_version_id], "has already been taken"
    assert_raises(ActiveRecord::RecordNotUnique) do
      LibraryBuild.transaction(requires_new: true) do
        LibraryBuild.insert_all!([ build.attributes.except("id") ])
      end
    end
  end
end
