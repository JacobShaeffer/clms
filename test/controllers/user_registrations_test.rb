require "test_helper"

class UserRegistrationsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "signup form includes the required name field" do
    get new_user_registration_url

    assert_response :success
    assert_select "input[name='user[name]'][type='text'][required='required'][autocomplete='name'][autofocus='autofocus']", count: 1
    assert_select "input[name='user[email]'][autofocus]", count: 0
  end

  test "signup creates a user with the submitted name" do
    assert_difference("User.count", 1) do
      post user_registration_url, params: {
        user: {
          name: "Taylor Example",
          email: "taylor@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_redirected_to root_url
    assert_equal "Taylor Example", User.find_by!(email: "taylor@example.com").name
  end

  test "signup without a name displays the validation error" do
    assert_no_difference("User.count") do
      post user_registration_url, params: {
        user: {
          name: "",
          email: "missing-name@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Name can't be blank"
  end
end
