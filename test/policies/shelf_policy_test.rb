require "test_helper"

class ShelfPolicyTest < ActiveSupport::TestCase
  test "index requires a non-guest user" do
    refute ShelfPolicy.new(nil, Shelf).index?
    refute ShelfPolicy.new(users(:one), Shelf).index?

    users(:one).update!(role: :organization)

    assert ShelfPolicy.new(users(:one), Shelf).index?
  end

  test "scope contains only shelves owned by the user" do
    users(:one).update!(role: :organization)

    resolved_scope = ShelfPolicy::Scope.new(users(:one), Shelf.all).resolve

    assert_includes resolved_scope, shelves(:one)
    refute_includes resolved_scope, shelves(:two)
  end

  test "scope is empty for guests and anonymous users" do
    assert_empty ShelfPolicy::Scope.new(users(:one), Shelf.all).resolve
    assert_empty ShelfPolicy::Scope.new(nil, Shelf.all).resolve
  end
end
