require "test_helper"

class MetadataTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @metadata_type = metadata_types(:one)
  end

  test "should get index" do
    get metadata_types_url
    assert_response :success
  end

  test "metadata_values renders turbo frame" do
    get metadata_values_metadata_type_url(@metadata_type)

    assert_response :success
    assert_select "turbo-frame#metadata_type_#{@metadata_type.id}_metadata_values"
    assert_select ".metadata-value-row", 1
  end

  test "metadata_values filters by search query" do
    create_metadatum!(name: "Search Match", under_review: false)
    create_metadatum!(name: "Hidden Value", under_review: false)

    get metadata_values_metadata_type_url(@metadata_type), params: { q: "Match" }

    assert_response :success
    assert_includes @response.body, "Search Match"
    refute_includes @response.body, "Hidden Value"
  end

  test "metadata_values filters by review status" do
    create_metadatum!(name: "Needs Review", under_review: true)
    create_metadatum!(name: "Already Reviewed", under_review: false)

    get metadata_values_metadata_type_url(@metadata_type), params: { status: "under_review" }

    assert_response :success
    assert_includes @response.body, "Needs Review"
    refute_includes @response.body, "Already Reviewed"
  end

  test "metadata_values limits initial result count" do
    6.times do |index|
      create_metadatum!(name: "Limited Value #{index}", under_review: false)
    end

    get metadata_values_metadata_type_url(@metadata_type)

    assert_response :success
    assert_select ".metadata-value-row", 5
    assert_select "a", "Show More"
  end

  test "should get new" do
    get new_metadata_type_url
    assert_response :success
  end

  test "should create metadata_type" do
    assert_difference("MetadataType.count") do
      post metadata_types_url, params: { metadata_type: {} }
    end

    assert_redirected_to metadata_type_url(MetadataType.last)
  end

  test "should show metadata_type" do
    get metadata_type_url(@metadata_type)
    assert_response :success
  end

  test "should get edit" do
    get edit_metadata_type_url(@metadata_type)
    assert_response :success
  end

  test "should update metadata_type" do
    patch metadata_type_url(@metadata_type), params: { metadata_type: {} }
    assert_redirected_to metadata_type_url(@metadata_type)
  end

  test "should destroy metadata_type" do
    assert_difference("MetadataType.count", -1) do
      delete metadata_type_url(@metadata_type)
    end

    assert_redirected_to metadata_types_url
  end

  private
    def create_metadatum!(name:, under_review:)
      Metadatum.create!(
        metadata_type: @metadata_type,
        user: users(:one),
        name: name,
        under_review: under_review
      )
    end
end
