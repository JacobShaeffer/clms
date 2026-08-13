require "test_helper"

class ContentTablePreferenceTest < ActiveSupport::TestCase
  test "belongs to a user and defaults to empty state" do
    preference = ContentTablePreference.new(user: users(:one), table_key: "contents.index")

    assert_predicate preference, :valid?
    assert_equal({}, preference.state)
  end

  test "requires a table key" do
    preference = ContentTablePreference.new(user: users(:one), table_key: "", state: {})

    assert_not preference.valid?
    assert_includes preference.errors[:table_key], "can't be blank"
  end

  test "requires an owner" do
    preference = ContentTablePreference.new(table_key: "contents.index", state: {})

    assert_not preference.valid?
    assert_includes preference.errors[:user], "must exist"
  end

  test "requires state to be an object" do
    preference = ContentTablePreference.new(user: users(:one), table_key: "contents.index", state: [])

    assert_not preference.valid?
    assert_includes preference.errors[:state], "must be an object"
  end

  test "requires a table key to be unique per user" do
    ContentTablePreference.create!(user: users(:one), table_key: "contents.index", state: {})

    duplicate = ContentTablePreference.new(user: users(:one), table_key: "contents.index", state: {})
    other_user = ContentTablePreference.new(user: users(:two), table_key: "contents.index", state: {})

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:table_key], "has already been taken"
    assert_predicate other_user, :valid?
  end

  test "atomically inserts and updates state" do
    preference = ContentTablePreference.save_state!(
      user: users(:one),
      table_key: "contents.index",
      state: { "q" => "first" }
    )

    travel 1.second do
      assert_no_difference("ContentTablePreference.count") do
        updated_preference = ContentTablePreference.save_state!(
          user: users(:one),
          table_key: "contents.index",
          state: { "q" => "second" }
        )

        assert_equal preference, updated_preference
        assert_equal({ "q" => "second" }, updated_preference.state)
        assert_operator updated_preference.updated_at, :>, preference.updated_at
      end
    end
  end

  test "atomic saving enforces preference invariants" do
    assert_raises(ArgumentError) do
      ContentTablePreference.save_state!(user: users(:one), table_key: "", state: {})
    end
    assert_raises(ArgumentError) do
      ContentTablePreference.save_state!(user: users(:one), table_key: "contents.index", state: [])
    end
    assert_raises(ArgumentError) do
      ContentTablePreference.save_state!(
        user: User.new,
        table_key: "contents.index",
        state: {}
      )
    end
  end

  test "destroying a user destroys its preferences" do
    user = User.create!(
      name: "Preference Owner",
      email: "preference-owner@example.com",
      password: "password"
    )
    ContentTablePreference.create!(user:, table_key: "contents.index", state: {})

    assert_difference("ContentTablePreference.count", -1) { user.destroy! }
  end
end
