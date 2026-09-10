require "test_helper"

class ContentTables::PageNavigationTest < ActiveSupport::TestCase
  test "round trips the ordered content ids for the same user" do
    token = ContentTables::PageNavigation.token_for(
      user: users(:one),
      records: [ contents(:two), contents(:one) ]
    )

    assert_equal [ contents(:two).id, contents(:one).id ],
      ContentTables::PageNavigation.content_ids_for(user: users(:one), token:)
  end

  test "rejects another user and a changed token" do
    token = ContentTables::PageNavigation.token_for(
      user: users(:one),
      records: [ contents(:one) ]
    )

    assert_empty ContentTables::PageNavigation.content_ids_for(user: users(:two), token:)
    assert_empty ContentTables::PageNavigation.content_ids_for(user: users(:one), token: "#{token}changed")
  end
end
