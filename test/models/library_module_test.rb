require "test_helper"

class LibraryModuleTest < ActiveSupport::TestCase
  test "is valid with a name folder name and icon" do
    library_module = build_module

    assert library_module.valid?
  end

  test "requires a name folder name and icon" do
    library_module = LibraryModule.new(user: users(:one))

    refute library_module.valid?
    assert_includes library_module.errors[:name], "can't be blank"
    assert_includes library_module.errors[:folder_name], "can't be blank"
    assert_includes library_module.errors[:icon], "must exist"
  end

  test "allows duplicate names" do
    first = build_module
    second = build_module

    assert first.save
    assert second.save
  end

  test "prevents deleting an icon used by a module" do
    library_module = build_module
    library_module.save!

    refute library_module.icon.destroy
    assert LibraryAsset.exists?(library_module.icon_id)
    assert_includes library_module.icon.errors[:base], "Cannot delete record because dependent library modules exist"
  end

  private

  def build_module
    LibraryModule.new(
      user: users(:one),
      name: "First Aid",
      folder_name: "first-aid",
      icon: library_assets(:one)
    )
  end
end
