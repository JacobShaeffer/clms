require "application_system_test_case"

class ContentsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(role: :organization)
    @user.active_shelves.delete_all
    @shelf = shelves(:one)
    ActiveShelf.activate!(user: @user, shelf: @shelf)
    sign_in @user
  end

  test "adds selected content while keeping the shelf dropdown open" do
    content = contents(:two)

    visit contents_path
    find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
    click_button "Shelves"
    check @shelf.name

    within ".shelf-selection-menu" do
      click_button "Add to Shelves"
      assert_text "Content was added to the selected shelves."
    end

    assert_selector ".shelf-selection-menu.show"
    assert_no_selector "input[data-content-table-selection-target='row']:checked"
    assert_no_selector "input[name='shelf_ids[]']:checked"
    assert ShelfContent.exists?(shelf: @shelf, content:)
  end

  test "table replacement does not retain selected rows" do
    content = contents(:one)

    visit contents_path
    find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
    find("thead a[aria-label='Sort Title ascending']").click

    assert_no_selector "input[data-content-table-selection-target='row']:checked"
  end
end
