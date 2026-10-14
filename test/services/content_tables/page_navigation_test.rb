require "test_helper"

class ContentTables::PageNavigationTest < ActiveSupport::TestCase
  test "round trips the ordered content ids and table id for the same user" do
    token = ContentTables::PageNavigation.token_for(
      user: users(:one),
      records: [ contents(:two), contents(:one) ],
      table_id: "contents_table"
    )
    context = ContentTables::PageNavigation.context_for(user: users(:one), token:)

    assert_equal [ contents(:two).id, contents(:one).id ],
      context.content_ids
    assert_equal "contents_table", context.table_id
    assert_equal context.content_ids,
      ContentTables::PageNavigation.content_ids_for(user: users(:one), token:)
  end

  test "rejects another user and a changed token" do
    token = ContentTables::PageNavigation.token_for(
      user: users(:one),
      records: [ contents(:one) ],
      table_id: "contents_table"
    )

    other_user_context = ContentTables::PageNavigation.context_for(user: users(:two), token:)
    changed_token_context = ContentTables::PageNavigation.context_for(
      user: users(:one),
      token: "#{token}changed"
    )

    assert_empty other_user_context.content_ids
    assert_nil other_user_context.table_id
    assert_empty changed_token_context.content_ids
    assert_nil changed_token_context.table_id
  end

  test "rejects missing and expired tokens" do
    missing_context = ContentTables::PageNavigation.context_for(
      user: users(:one),
      token: nil
    )
    token = ContentTables::PageNavigation.token_for(
      user: users(:one),
      records: [ contents(:one) ],
      table_id: "contents_table"
    )

    travel ContentTables::PageNavigation::EXPIRATION + 1.second do
      expired_context = ContentTables::PageNavigation.context_for(user: users(:one), token:)

      assert_empty expired_context.content_ids
      assert_nil expired_context.table_id
    end
    assert_empty missing_context.content_ids
    assert_nil missing_context.table_id
  end
end
