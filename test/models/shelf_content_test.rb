require "test_helper"

class ShelfContentTest < ActiveSupport::TestCase
  test "belongs to a shelf and content" do
    shelf_content = shelf_contents(:one)

    assert_equal shelves(:one), shelf_content.shelf
    assert_equal contents(:one), shelf_content.content
  end
end
