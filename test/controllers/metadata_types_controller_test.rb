require "test_helper"

class MetadataTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @metadata_type = metadata_types(:one)
  end

  test "should get index" do
    get metadata_types_url
    assert_response :success
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
end
