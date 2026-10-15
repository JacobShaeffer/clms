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

  test "current version must be editable" do
    library = Library.create!(name: "Health Library", user: users(:one))
    locked_version = library.current_version
    LibraryVersions::Create.call(library:, version_number: "2.0", user: users(:one))

    library.current_version = locked_version

    assert_not library.valid?
    assert_includes library.errors[:current_version], "must be editable"
  end

  test "name is required" do
    library = Library.new(name: "", user: users(:one))

    assert_not library.valid?
    assert_includes library.errors[:name], "can't be blank"
  end

  test "banner is optional" do
    library = Library.create!(name: "Health Library", user: users(:one))

    assert_nil library.banner
  end

  test "accepts only Banner library assets as the banner" do
    library = Library.create!(name: "Health Library", user: users(:one))
    banner = build_asset("Banner")
    subject = build_asset("Subject")
    banner.save!
    subject.save!

    assert library.update(banner: banner)

    library.banner = subject
    refute library.valid?
    assert_includes library.errors[:banner], "must be a Banner library asset"
  end

  private

  def build_asset(asset_type)
    LibraryAsset.new(
      user: users(:one),
      name: "#{asset_type} #{SecureRandom.hex(4)}",
      asset_type: asset_type
    ).tap do |asset|
      asset.image.attach(
        io: StringIO.new("PNG contents"),
        filename: "#{asset_type.downcase}.png",
        content_type: "image/png"
      )
    end
  end
end
