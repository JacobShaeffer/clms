require "test_helper"

class ShelvesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(role: :organization)
    sign_in users(:one)
  end

  test "index lists only the current user's shelves in name order" do
    shelves(:one).update!(name: "Zebra shelf")
    first_shelf = users(:one).shelves.create!(name: "Archive shelf")

    get shelves_url

    assert_response :success
    assert_select "h1", text: "Shelves"
    assert_select "table.table.table-striped.table-hover.align-middle"
    assert_select "tbody#shelves tr", count: 2
    assert_select "tbody#shelves tr:nth-child(1)##{ActionView::RecordIdentifier.dom_id(first_shelf)} td", text: "Archive shelf"
    assert_select "tbody#shelves tr:nth-child(2)##{ActionView::RecordIdentifier.dom_id(shelves(:one))} td", text: "Zebra shelf"
    assert_select "tbody#shelves", text: shelves(:two).name, count: 0
  end

  test "index renders an empty state" do
    users(:one).shelves.destroy_all

    get shelves_url

    assert_response :success
    assert_select "tbody#shelves td.text-center", text: "No shelves found."
  end

  test "guest cannot access shelves or see the content dropdown" do
    sign_out users(:one)
    sign_in users(:two)

    get shelves_url

    assert_redirected_to root_url
    follow_redirect!
    assert_select "#content-navigation a[href='#{contents_path}']", text: "Content", count: 1
    assert_select "#content-navigation button.dropdown-toggle", count: 0
    assert_select "#content-navigation a[href='#{shelves_path}']", count: 0
  end

  test "anonymous user must sign in" do
    sign_out users(:one)

    get shelves_url

    assert_redirected_to new_user_session_url
  end
end
