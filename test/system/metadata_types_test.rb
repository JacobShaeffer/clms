require "application_system_test_case"

class MetadataTypesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @first_type = metadata_types(:one)
    @second_type = metadata_types(:two)
    @first_type.update!(name: "Subject", order: 1)
    @second_type.update!(name: "Language", order: 2)
    sign_in @admin
  end

  test "reorders metadata types in the modal" do
    visit metadata_types_path

    find("[aria-label='Edit metadata types']").click
    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "Edit metadata types"
      find("button[aria-label='Move Language up']").click
      assert_equal [ @second_type.id, @first_type.id ],
        all("input[name='metadata_type_ids[]']", visible: :all).map { |input| input.value.to_i }
      click_button "Save"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_equal [ @second_type, @first_type ], MetadataType.in_display_order.to_a
    assert_equal [
      "metadata_type_#{@second_type.id}",
      "metadata_type_#{@first_type.id}"
    ], all("#metadata-types > div").map { |element| element[:id] }
  end

  test "edits a metadata type in the modal" do
    visit metadata_types_path

    find("[aria-label='Edit metadata types']").click

    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "Edit metadata types"
      fill_in "Name for Subject", with: "Topic"
      select "Volunteer", from: "Access level for Subject"
      click_button "Save"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_equal [ "Topic", User.roles.fetch("volunteer") ], @first_type.reload.values_at(:name, :access_level)
    assert_selector "#metadata_type_#{@first_type.id}", text: "Topic"
  end
end
