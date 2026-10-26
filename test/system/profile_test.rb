require "application_system_test_case"

class ProfileTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "profile dropdown opens and logs out the signed in user" do
    user = users(:one)
    user.update!(role: :volunteer)
    sign_in user

    visit root_path
    within "#profile-navigation" do
      assert_no_button "Logout"
      click_button "Profile"
      assert_selector "button#profile-menu[aria-expanded='true']"
      within ".dropdown-menu.show" do
        click_button "Logout"
      end
    end

    assert_current_path root_path
    assert_no_selector "#profile-navigation"
    within "#authentication-navigation" do
      click_link "Sign up"
    end
    assert_current_path new_user_registration_path
    within "#authentication-navigation" do
      click_link "Login"
    end
    assert_current_path new_user_session_path
    assert_no_selector "#profile-navigation"
  end
end
