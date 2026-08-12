require "test_helper"

class MetadataTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_STREAM_HEADERS = {
    "Turbo-Frame" => "modal",
    "Accept" => "text/vnd.turbo-stream.html"
  }.freeze

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @metadata_type = metadata_types(:one)
    sign_in @admin
  end

  test "index renders metadata types and their value counts" do
    get metadata_types_url

    assert_response :success
    assert_select "#metadata_type_#{@metadata_type.id}" do
      assert_select ".accordion-button", text: /#{Regexp.escape(@metadata_type.name)}/
      assert_select "#metadata_count_metadata_type_#{@metadata_type.id}", text: @metadata_type.metadata.count.to_s
    end
  end

  test "metadata values combine search and review filters" do
    create_metadatum!(name: "Matching reviewed", under_review: false)
    create_metadatum!(name: "Matching pending", under_review: true)
    create_metadatum!(name: "Different reviewed", under_review: false)

    get metadata_values_metadata_type_url(@metadata_type), params: { q: "Matching", status: "reviewed" }

    assert_response :success
    assert_select "turbo-frame#metadata_values_metadata_type_#{@metadata_type.id}"
    assert_select ".metadata-value-row", 1
    assert_includes response.body, "Matching reviewed"
    refute_includes response.body, "Matching pending"
    refute_includes response.body, "Different reviewed"
  end

  test "metadata values enforce page limits" do
    6.times { |index| create_metadatum!(name: "Limited value #{index}", under_review: false) }

    get metadata_values_metadata_type_url(@metadata_type), params: { limit: 1 }

    assert_response :success
    assert_select ".metadata-value-row", 5
    assert_select "a", text: "Show More"

    get metadata_values_metadata_type_url(@metadata_type), params: { limit: 1_000 }

    assert_response :success
    assert_select ".metadata-value-row", @metadata_type.metadata.count
    assert_select "a", text: "Show More", count: 0
  end

  test "create prepends a metadata type from the modal" do
    assert_difference("MetadataType.count") do
      post metadata_types_url,
        params: { metadata_type: { name: "New subject", order: 3, access_level: 2 } },
        headers: TURBO_STREAM_HEADERS
    end

    created = MetadataType.find_by!(name: "New subject")
    assert_equal @admin, created.user
    assert_equal 2, created.access_level
    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='prepend'][target='metadata-types']"
  end

  test "invalid create rerenders the modal with errors" do
    assert_no_difference("MetadataType.count") do
      post metadata_types_url,
        params: { metadata_type: { name: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger"
  end

  test "update changes permitted attributes" do
    patch metadata_type_url(@metadata_type), params: {
      metadata_type: { name: "Updated subject", order: 7, access_level: 3 }
    }

    assert_redirected_to metadata_type_url(@metadata_type)
    assert_equal [ "Updated subject", 7, 3 ], @metadata_type.reload.values_at(:name, :order, :access_level)
  end

  test "only an admin can destroy a metadata type" do
    sign_out @admin
    @admin.update!(role: :intern_plus)
    sign_in @admin

    assert_no_difference("MetadataType.count") do
      delete metadata_type_url(@metadata_type)
    end
    assert_redirected_to root_url

    sign_out @admin
    @admin.update!(role: :admin)
    sign_in @admin

    assert_difference("MetadataType.count", -1) do
      delete metadata_type_url(@metadata_type)
    end
    assert_redirected_to metadata_types_url
  end

  test "unauthenticated users are redirected" do
    sign_out @admin

    get metadata_types_url

    assert_redirected_to new_user_session_url
  end

  private

  def create_metadatum!(name:, under_review:)
    Metadatum.create!(
      metadata_type: @metadata_type,
      user: @admin,
      name: name,
      under_review: under_review
    )
  end
end
