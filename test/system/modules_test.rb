require "application_system_test_case"

class ModulesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(role: :admin)
    sign_in users(:one)
  end

  test "searches and manages modules through modal actions" do
    existing = LibraryModule.create!(
      user: users(:one),
      name: "Existing Module",
      folder_name: "existing",
      icon: library_assets(:one)
    )
    visit modules_path

    fill_in "Search by name", with: "missing"
    assert_text "No modules match your search."
    fill_in "Search by name", with: ""
    assert_selector "##{ActionView::RecordIdentifier.dom_id(existing)}"

    click_on "New Module"
    within "#modal" do
      fill_in "Name", with: "First Aid"
      fill_in "Folder Name", with: "first-aid"
      select library_assets(:two).display_name, from: "Icon"
      click_button "Create Module"
    end
    assert_no_selector "#modal .modal"

    created = LibraryModule.find_by!(name: "First Aid")
    within "##{ActionView::RecordIdentifier.dom_id(created)}" do
      assert_text "first-aid"
      assert_text library_assets(:two).display_name
      find("a[aria-label='Show First Aid']").click
    end

    within "#modal" do
      assert_text "First Aid"
      assert_text "first-aid"
      click_on "Edit"
    end
    within "#modal" do
      fill_in "Name", with: "Emergency Care"
      click_button "Update Module"
    end
    assert_no_selector "#modal .modal"

    within "##{ActionView::RecordIdentifier.dom_id(created)}" do
      assert_text "Emergency Care"
      find("a[aria-label='Destroy Emergency Care']").click
    end
    within "#modal" do
      click_button "Delete"
    end

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(created)}"
    refute LibraryModule.exists?(created.id)
  end
end
