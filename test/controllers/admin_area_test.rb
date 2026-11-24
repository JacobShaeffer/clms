require "test_helper"

class AdminAreaTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @user = users(:two)
    sign_in @admin
  end

  test "non-admin cannot view or change admin pages" do
    sign_out @admin
    sign_in @user
    get admin_curator_stats_path, params: { timezone: "America/Phoenix" }
    assert_redirected_to root_path
    patch toggle_active_admin_user_path(@admin)
    assert_redirected_to root_path
    assert @admin.reload.active?
  end

  test "admin creates edits and deactivates a user while retaining content" do
    post admin_users_path, params: { user: { name: "New User", email: "new@example.com", role: "volunteer", password: "password", password_confirmation: "password" } }
    assert_redirected_to admin_users_path
    created = User.find_by!(email: "new@example.com")
    patch admin_user_path(created), params: { user: { name: "Changed", email: created.email, role: "intern", password: "", password_confirmation: "" } }
    assert_equal "Changed", created.reload.name
    assert created.intern?
    patch toggle_active_admin_user_path(@user)
    assert_not @user.reload.active?
    assert Content.exists?(id: contents(:two).id)
    patch toggle_active_admin_user_path(@user)
    assert @user.reload.active?
  end

  test "user search matches name or email case insensitively and treats wildcards literally" do
    @user.update!(name: "Alex Curator", email: "alex@example.com")
    get admin_users_path, params: { q: "cURAtor" }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody td", text: "Alex Curator"

    get admin_users_path, params: { q: "EXAMPLE.COM", sort: "email", direction: "desc" }
    assert_select "tbody tr", count: 2
    assert_select "input[name=q][value='EXAMPLE.COM']"
    assert_select "th[aria-sort=descending] a[aria-label='Sort Email ascending'][href*='q=EXAMPLE.COM']"

    get admin_users_path, params: { q: "%" }
    assert_select "tbody tr", count: 0
    assert_select "p", text: "No users found."
  end

  test "user columns sort in either direction by their displayed values" do
    @admin.update!(name: "Zoe", email: "a@example.com", role: :admin)
    @user.update!(name: "alice", email: "z@example.com", role: :volunteer, active: false)
    expected = {
      "name" => [ "alice", "Zoe" ],
      "email" => [ "Zoe", "alice" ],
      "role" => [ "Zoe", "alice" ],
      "status" => [ "Zoe", "alice" ]
    }
    expected.each do |column, names|
      %w[asc desc].each do |direction|
        get admin_users_path, params: { sort: column, direction: direction }
        assert_response :success
        actual = css_select("tbody tr").map { |row| row.css("td").first.text.strip }
        assert_equal direction == "asc" ? names : names.reverse, actual, "#{column} #{direction}"
      end
    end
  end

  test "invalid sort parameters fall back to name ascending" do
    get admin_users_path, params: { sort: "name; DROP TABLE users", direction: "invalid" }
    assert_response :success
    assert_select "th[aria-sort=ascending] a[aria-label='Sort Name descending']"
  end

  test "deactivated user loses existing session" do
    sign_out @admin
    sign_in @user
    @user.update!(active: false)
    get contents_path
    assert_redirected_to new_user_session_path
    post user_session_path, params: { user: { email: @user.email, password: "password" } }
    assert_not_equal @user.id, session["warden.user.user.key"]&.dig(0, 0)
  end

  test "last active administrator cannot be deactivated or demoted" do
    patch toggle_active_admin_user_path(@admin)
    assert @admin.reload.active?
    patch admin_user_path(@admin), params: { user: { name: @admin.name, email: @admin.email, role: "volunteer" } }
    assert_response :unprocessable_content
    assert @admin.reload.admin?
  end

  test "report uses local date bounds and keeps counts linked to content" do
    contents(:one).update_columns(created_at: Time.utc(2026, 3, 8, 7, 30), trashed_at: nil)
    contents(:two).update_columns(created_at: Time.utc(2026, 3, 9, 6, 30), trashed_at: nil)
    params = { timezone: "America/Los_Angeles", start_date: "2026-03-08", end_date: "2026-03-08" }
    get admin_curator_stats_path, params: params
    assert_response :success
    assert_select "a[href*='user_id=#{@user.id}']", text: "1"
    get admin_curator_content_path, params: params.merge(user_id: @user.id)
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody", text: /#{contents(:two).display_title}/
  end

  test "unknown or missing timezone falls back to UTC without a prompt" do
    get admin_curator_stats_path, params: { timezone: "not/a-zone" }
    assert_response :success
    assert_select "select[name=timezone]", count: 0
    assert_select "input[name=timezone][value='Etc/UTC']"
    assert_no_match "Dates shown in", response.body

    get admin_curator_content_path
    assert_response :success
    assert_select "select[name=timezone]", count: 0
    assert_no_match "Dates shown in", response.body
  end

  test "invalid dates do not query a report" do
    get admin_curator_stats_path, params: { timezone: "UTC", start_date: "bad", end_date: "2026-01-01" }
    assert_response :success
    assert_match "Enter valid dates", response.body
    assert_select "a", text: "Return to current week"
  end

  test "week selection preserves curator filters" do
    get admin_curator_content_path, params: { timezone: "America/Phoenix", week: "2026-01-04", user_id: @user.id, severity: "danger" }
    assert_response :success
    assert_select "summary", text: "Week of Dec 29, 2025"
    assert_select "input[type=date]", count: 0
    assert_select "[data-admin-week-picker-target=form]" do
      assert_select "input[name=user_id][value='#{@user.id}']"
      assert_select "input[name=severity][value=danger]"
      assert_select "input[name=week]"
    end
    assert_select "a[href*='week=2025-12-22'][href*='severity=danger'][href*='user_id=#{@user.id}']", text: "Previous week"
    assert_select "a[href*='severity=danger'][href*='user_id=#{@user.id}']", text: "Current week"
    assert_select "a[href*='week=2026-01-05'][href*='severity=danger'][href*='user_id=#{@user.id}']", text: "Next week"
    assert_select "input[type=week]", count: 0
    assert_select "input[type=submit][value='Show week']", count: 0
  end

  test "flag totals and linked filtered lists use the same rules" do
    [ contents(:one), contents(:two) ].each do |content|
      content.update_columns(created_at: Time.utc(2026, 1, 7, 12), trashed_at: nil)
    end
    contents(:one).update_columns(description: nil, display_title: nil)
    report = { timezone: "UTC", start_date: "2026-01-05", end_date: "2026-01-11" }
    get admin_curator_stats_path, params: report
    assert_response :success
    assert_select "a[href*='severity=danger'][href*='user_id=#{@admin.id}']", text: "1"
    assert_select "a[href*='severity=warning'][href*='user_id=#{@user.id}']", text: "1"
    get admin_curator_content_path, params: report.merge(user_id: @admin.id, severity: "danger")
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "i.text-danger", count: 1
  end

  test "logs page works without a configured log service" do
    get admin_logs_path
    assert_response :success
    assert_match "not configured", response.body
  end

  test "content pagination preserves the report scope" do
    Content.insert_all!(26.times.map do |index|
      { user_id: @user.id, title: "Page #{index}", display_title: "Page #{index}", description: "Description", created_at: Time.utc(2026, 1, 7, 12), updated_at: Time.current }
    end)
    report = { timezone: "America/Phoenix", start_date: "2026-01-05", end_date: "2026-01-11", user_id: @user.id }
    get admin_curator_content_path, params: report
    assert_response :success
    assert_select "a[href*='page=2'][href*='timezone=America%2FPhoenix'][href*='user_id=#{@user.id}']"
    get admin_curator_content_path, params: report.merge(page: 2)
    assert_response :success
    assert_select "tbody tr", count: 1
  end
end
