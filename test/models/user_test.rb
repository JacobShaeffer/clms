require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to the guest role" do
    user = User.new

    assert user.guest?
  end

  test "requires a name" do
    user = User.new(email: "nameless@example.com", password: "password")

    refute user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end
end
