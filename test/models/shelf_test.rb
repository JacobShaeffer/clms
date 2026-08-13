require "test_helper"

class ShelfTest < ActiveSupport::TestCase
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
