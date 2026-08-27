require "test_helper"

class MetadataControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @metadata_type = metadata_types(:one)
    @metadatum = Metadatum.find_by!(metadata_type: @metadata_type)
    sign_in @admin
  end

  test "new renders a nested modal form" do
    get new_metadata_type_metadatum_url(@metadata_type), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select "form[action='#{metadata_type_metadata_path(@metadata_type)}'][data-turbo-frame='modal']"
    assert_select "input[name='metadatum[name]']"
  end

  test "metadata type access level controls who can add values" do
    @metadata_type.update!(access_level: User.roles.fetch("volunteer"))
    sign_out @admin
    @admin.update!(role: :organization)
    sign_in @admin

    get new_metadata_type_metadatum_url(@metadata_type), headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    assert_no_difference("Metadatum.count") do
      post metadata_type_metadata_url(@metadata_type), params: { metadatum: { name: "Blocked value" } }
    end
    assert_redirected_to root_url

    sign_out @admin
    @admin.update!(role: :volunteer)
    sign_in @admin

    get new_metadata_type_metadatum_url(@metadata_type), headers: TURBO_FRAME_HEADERS
    assert_response :success
  end

  test "create updates the metadata list and count" do
    assert_difference("Metadatum.count") do
      post metadata_type_metadata_url(@metadata_type),
        params: { metadatum: { name: "New value", under_review: false } },
        headers: TURBO_STREAM_HEADERS
    end

    created = Metadatum.find_by!(metadata_type: @metadata_type, name: "New value")
    assert_equal @admin, created.user
    refute created.under_review?
    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='metadata_values_metadata_type_#{@metadata_type.id}']"
    assert_select "turbo-stream[action='update'][target='metadata_count_metadata_type_#{@metadata_type.id}']"
  end

  test "invalid create rerenders the modal with errors" do
    assert_no_difference("Metadatum.count") do
      post metadata_type_metadata_url(@metadata_type),
        params: { metadatum: { name: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger"
  end

  test "edit and update preserve metadata frame state" do
    frame_params = { q: "value", status: "reviewed", limit: 10 }

    get edit_metadata_type_metadatum_url(@metadata_type, @metadatum, frame_params), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "form[action*='q=value'][action*='status=reviewed'][action*='limit=10']"

    patch metadata_type_metadatum_url(@metadata_type, @metadatum, frame_params),
      params: { metadatum: { name: "Updated value" } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal "Updated value", @metadatum.reload.name
    assert_select "turbo-stream[action='replace'][target='metadata_values_metadata_type_#{@metadata_type.id}']"
  end

  test "toggle review updates the list without closing the modal" do
    previous_value = @metadatum.under_review?

    patch toggle_review_metadata_type_metadatum_url(@metadata_type, @metadatum), headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal !previous_value, @metadatum.reload.under_review?
    assert_select "turbo-stream[action='update'][target='modal']", count: 0
    assert_select "turbo-stream[action='replace'][target='metadata_values_metadata_type_#{@metadata_type.id}']"
  end

  test "metadata value renders status and overflow action dropdowns" do
    get metadata_values_metadata_type_url(@metadata_type)

    assert_response :success
    row = css_select("#metadatum_#{@metadatum.id}").first
    assert_equal "Reviewed", row.css(".col-sm-5 button.badge[data-bs-toggle='dropdown']").text.strip
    assert_equal [ "Mark for Review", "See all tagged items" ],
      row.css(".col-sm-5 .dropdown-menu .dropdown-item").map { |item| item.text.strip }
    assert_equal [ "Edit", "Replace", "Mark for Review", "See all tagged items", "Delete" ],
      row.css(".col-sm-1 .dropdown-menu .dropdown-item").map { |item| item.text.strip }
  end

  test "replace confirmation lists only other same-type values in alphabetical order" do
    later = create_metadatum!(name: "Zulu", under_review: true)
    earlier = create_metadatum!(name: "Alpha")
    frame_params = { q: "value", status: "reviewed", limit: 10 }

    get replace_confirmation_metadata_type_metadatum_url(@metadata_type, @metadatum, frame_params),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Replace metadata value"
    assert_select ".modal-dialog.modal-dialog-centered.modal-dialog-scrollable.metadata-replacement-dialog"
    assert_select "form.modal-content.metadata-replacement-form" do
      assert_select ".modal-body .metadata-replacement-options[role='radiogroup'][aria-label='Replacement value']"
      assert_select ".modal-footer input[type='submit'][value='Replace']"
      assert_select ".modal-footer button", text: "Cancel"
    end
    assert_select "input[type='radio'][name='replacement_id']", 2
    assert_select "input[type='radio'][value='#{@metadatum.id}']", count: 0
    other_type_value = Metadatum.find_by!(metadata_type: metadata_types(:two))
    assert_select "input[type='radio'][value='#{other_type_value.id}']", count: 0
    assert_select "form[data-controller='metadata-replacement-search']" do
      assert_select "label.form-label", text: "Search metadata values"
      assert_select "input[type='search'][data-action='input->metadata-replacement-search#filter']"
    end
    assert_equal [ earlier.name, later.name ],
      css_select(".metadata-replacement-name").map { |item| item.text.strip }
    assert_equal [ "Reviewed", "Under Review" ],
      css_select(".list-group-item .badge").map { |item| item.text.strip }
    form_action = css_select("form").first["action"]
    assert_includes form_action, "q=value"
    assert_includes form_action, "status=reviewed"
    assert_includes form_action, "limit=10"
  end

  test "replace confirmation disables replacement when there are no candidates" do
    get replace_confirmation_metadata_type_metadatum_url(@metadata_type, @metadatum),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "input[type='search'][disabled]", 1
    assert_select "input[type='radio'][name='replacement_id']", count: 0
    assert_select "input[type='submit'][value='Replace'][disabled]", 1
    assert_select ".text-muted", text: "No other metadata values are available for replacement."
  end

  test "replace moves references, removes overlaps, deletes the original, and refreshes the list" do
    replacement = create_metadatum!(name: "Replacement", under_review: true, user: users(:two))
    overlapping_content = contents(:two)
    ContentMetadatum.create!(content: overlapping_content, metadata: @metadatum)
    ContentMetadatum.create!(content: overlapping_content, metadata: replacement)
    replacement_attributes = replacement.attributes.slice("name", "user_id", "under_review")

    assert_difference("Metadatum.count", -1) do
      patch replace_metadata_type_metadatum_url(@metadata_type, @metadatum),
        params: { replacement_id: replacement.id },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    refute Metadatum.exists?(@metadatum.id)
    assert_equal [ contents(:one).id, overlapping_content.id ].sort,
      ContentMetadatum.where(metadata: replacement).pluck(:content_id).sort
    assert_equal 1, ContentMetadatum.where(metadata: replacement, content: overlapping_content).count
    assert_equal replacement_attributes, replacement.reload.attributes.slice("name", "user_id", "under_review")
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='metadata_values_metadata_type_#{@metadata_type.id}']"
    assert_select "turbo-stream[action='update'][target='metadata_count_metadata_type_#{@metadata_type.id}']", text: "1"
  end

  test "replace rejects missing, self, and cross-type replacement values" do
    other_type_value = Metadatum.find_by!(metadata_type: metadata_types(:two))

    [ nil, @metadatum.id, other_type_value.id ].each do |replacement_id|
      assert_no_difference([ "Metadatum.count", "ContentMetadatum.count" ]) do
        patch replace_metadata_type_metadatum_url(@metadata_type, @metadatum),
          params: { replacement_id: replacement_id },
          headers: TURBO_STREAM_HEADERS
      end

      assert_response :unprocessable_content
      assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger",
        text: "Select a valid replacement value."
    end
  end

  test "replace requires delete-level permission" do
    replacement = create_metadatum!(name: "Replacement")
    sign_out @admin
    @admin.update!(role: :intern)
    sign_in @admin

    assert_no_difference([ "Metadatum.count", "ContentMetadatum.count" ]) do
      patch replace_metadata_type_metadatum_url(@metadata_type, @metadatum),
        params: { replacement_id: replacement.id },
        headers: TURBO_STREAM_HEADERS
    end

    assert_redirected_to root_url
    assert Metadatum.exists?(@metadatum.id)
  end

  test "delete confirmation and destroy use the nested resource" do
    get delete_confirmation_metadata_type_metadatum_url(@metadata_type, @metadatum), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Delete metadata value"
    assert_select "form[action='#{metadata_type_metadatum_path(@metadata_type, @metadatum)}']"

    assert_difference("Metadatum.count", -1) do
      delete metadata_type_metadatum_url(@metadata_type, @metadatum), headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='metadata_values_metadata_type_#{@metadata_type.id}']"
  end

  test "unauthenticated users are redirected" do
    sign_out @admin

    get new_metadata_type_metadatum_url(@metadata_type)

    assert_redirected_to new_user_session_url
  end

  private

  def create_metadatum!(name:, under_review: false, user: @admin)
    @metadata_type.metadata.create!(name: name, under_review: under_review, user: user)
  end
end
