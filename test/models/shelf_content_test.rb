require "test_helper"

class ShelfContentTest < ActiveSupport::TestCase
  test "belongs to a shelf and content" do
    shelf_content = shelf_contents(:one)

    assert_equal shelves(:one), shelf_content.shelf
    assert_equal contents(:one), shelf_content.content
  end

  test "a content item can only be placed on a shelf once" do
    duplicate = ShelfContent.new(shelf: shelves(:one), content: contents(:one))

    refute duplicate.valid?
    assert_includes duplicate.errors[:content_id], "has already been taken"

    assert_raises(ActiveRecord::RecordNotUnique) do
      ShelfContent.insert_all!([ { shelf_id: shelves(:one).id, content_id: contents(:one).id } ])
    end
  end
end
