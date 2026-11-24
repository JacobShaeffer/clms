require "application_system_test_case"

class AdminCuratorWeekTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    sign_in @admin
  end

  test "calendar starts on Monday and selecting a day updates the report and preserves filters" do
    visit admin_curator_content_path(timezone: "America/Phoenix", week: "2026-01-07", user_id: users(:two).id, severity: "warning")
    assert_no_text "Dates shown in"
    assert_no_button "Show week"
    assert_no_field "From"
    assert_no_field "Through"
    assert_link "Previous week"
    assert_link "Current week"
    assert_link "Next week"
    find("summary", text: "Week of Jan 5, 2026").click
    within ".admin-week-calendar" do
      assert_equal %w[Mon Tue Wed Thu Fri Sat Sun], all("thead th").map(&:text)
      assert_equal "2025-12-29", first("tbody tr button", visible: :all)["data-date"]
      find("button[data-date='2026-01-04']", visible: :all).click
    end
    assert_selector "summary", text: "Week of Dec 29, 2025"
    assert_equal users(:two).id.to_s, find_field("User").value
    assert_equal "warning", find_field("Flags").value
  end

  test "week navigation retains curator filters" do
    visit admin_curator_content_path(timezone: "America/Phoenix", week: "2026-01-07", user_id: users(:two).id, severity: "warning")
    click_link "Previous week"
    assert_selector "summary", text: "Week of Dec 29, 2025"
    click_link "Next week"
    assert_selector "summary", text: "Week of Jan 5, 2026"
    click_link "Current week"
    assert_equal users(:two).id.to_s, find_field("User").value
    assert_equal "warning", find_field("Flags").value
    assert_no_field "From"
    assert_no_field "Through"
  end

  test "keyboard moves across months and selects the week" do
    visit admin_curator_stats_path(timezone: "UTC", week: "2026-01-26")
    find("summary", text: "Week of Jan 26, 2026").click
    within ".admin-week-calendar" do
      button = find("button[data-date='2026-01-26']")
      button.send_keys(:arrow_up, :arrow_up, :arrow_up, :arrow_up)
    end
    assert_text "December 2025"
    find("button[data-date='2025-12-29']").send_keys(:enter)
    assert_selector "summary", text: "Week of Dec 29, 2025"
  end

  test "timezone is detected without a selection prompt" do
    visit admin_curator_stats_path
    assert_no_text "Select your timezone"
    assert_no_text "Dates shown in"
    assert_selector "[data-controller='admin-week-picker']"
    assert_match(/timezone=/, current_url)
  end
end
