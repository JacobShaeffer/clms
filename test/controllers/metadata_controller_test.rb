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
end
