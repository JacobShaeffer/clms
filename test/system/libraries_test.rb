require "application_system_test_case"

class LibrariesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(
      name: "Library System User",
      email: "library-system-user@example.com",
      password: "password",
      role: :intern_plus
    )
    sign_in users(:one)
  end

  test "clicking the version cell opens the library" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit libraries_path
    find("##{ActionView::RecordIdentifier.dom_id(library)} td", text: "1.0").click

    assert_current_path library_path(library)
    assert_selector "h1", text: library.name
  end

  test "creating a library from the modal adds it to the table" do
    visit libraries_path

    click_on "New library"

    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "New library"
      fill_in "Name", with: "Agriculture Library"
      click_on "Create Library"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_selector "tbody#libraries tr", text: /Agriculture Library.*1\.0/
  end
end
