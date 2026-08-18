require "test_helper"

class ShelfTest < ActiveSupport::TestCase
  test "requires a name" do
    shelf = users(:one).shelves.build(name: " ")

    refute shelf.valid?
    assert_includes shelf.errors[:name], "can't be blank"
  end

  test "belongs to a user and contains content through shelf contents" do
    shelf = shelves(:one)

    assert_equal users(:one), shelf.user
    assert_includes shelf.contents, contents(:one)
  end

  test "destroys its shelf contents" do
    shelf = shelves(:one)

    assert_difference("ShelfContent.count", -1) { shelf.destroy! }
  end

  test "destroys its active shelf record" do
    active_shelf = ActiveShelf.activate!(user: users(:one), shelf: shelves(:one))

    shelves(:one).destroy!

    refute ActiveShelf.exists?(active_shelf.id)
  end
end
