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

  test "replaces a metadata value from its action menu" do
    original = Metadatum.find_by!(metadata_type: metadata_types(:one))
    replacement = original.metadata_type.metadata.create!(user: @admin, name: "Replacement", under_review: true)
    other_candidate = original.metadata_type.metadata.create!(user: @admin, name: "Unrelated", under_review: false)

    visit metadata_types_path
    find("#metadata_type_#{original.metadata_type_id} .accordion-button").click

    within "#metadatum_#{original.id}" do
      find("button[aria-label='Metadata value actions']").click
      click_link "Replace"
    end

    short_modal_height = nil
    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "Replace metadata value"
      wait_for_replacement_modal
      short_modal_height = replacement_modal_height
      click_button "Cancel"
    end
    assert_no_selector "turbo-frame#modal .modal"

    30.times do |index|
      original.metadata_type.metadata.create!(user: @admin, name: format("ZZ Extra %02d", index))
    end

    within "#metadatum_#{original.id}" do
      find("button[aria-label='Metadata value actions']").click
      click_link "Replace"
    end

    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "Replace metadata value"
      wait_for_replacement_modal
      assert_in_delta short_modal_height, replacement_modal_height, 1
      top_gap = evaluate_script(
        "document.querySelector('.metadata-replacement-dialog .modal-content').getBoundingClientRect().top"
      )
      bottom_gap = evaluate_script(
        "window.innerHeight - document.querySelector('.metadata-replacement-dialog .modal-content').getBoundingClientRect().bottom"
      )
      assert_in_delta top_gap, bottom_gap, 2
      assert evaluate_script(
        "document.querySelector('.metadata-replacement-options').scrollHeight > " \
          "document.querySelector('.metadata-replacement-options').clientHeight"
      )
      assert evaluate_script(<<~JAVASCRIPT)
        (() => {
          const options = document.querySelector(".metadata-replacement-options")
          options.scrollTop = options.scrollHeight
          return options.scrollTop > 0
        })()
      JAVASCRIPT
      assert evaluate_script(<<~JAVASCRIPT)
        (() => {
          const content = document.querySelector(".metadata-replacement-dialog .modal-content").getBoundingClientRect()
          const footer = document.querySelector(".metadata-replacement-dialog .modal-footer").getBoundingClientRect()
          return footer.top >= content.top && footer.bottom <= content.bottom
        })()
      JAVASCRIPT
      assert_button "Replace"
      within ".list-group-item", text: replacement.name do
        assert_selector ".badge", text: "Under Review"
      end
      within ".list-group-item", text: other_candidate.name do
        assert_selector ".badge", text: "Reviewed"
      end
      fill_in "Search metadata values", with: "replace"
      assert_selector ".list-group-item", text: replacement.name
      assert_no_selector ".list-group-item", text: other_candidate.name
      choose replacement.name
      click_button "Replace"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_no_selector "#metadatum_#{original.id}"
    assert_selector "#metadatum_#{replacement.id}", text: replacement.name
    refute Metadatum.exists?(original.id)
    assert ContentMetadatum.exists?(metadata: replacement, content: contents(:one))
  end

  private

  def replacement_modal_height
    evaluate_script(
      "document.querySelector('.metadata-replacement-dialog .modal-content').getBoundingClientRect().height"
    )
  end

  def wait_for_replacement_modal
    evaluate_async_script(<<~JAVASCRIPT)
      const done = arguments[0]
      const dialog = document.querySelector(".metadata-replacement-dialog")

      if (getComputedStyle(dialog).transform === "none") {
        done()
      } else {
        dialog.addEventListener("transitionend", () => done(), { once: true })
      }
    JAVASCRIPT
  end
end
