require "test_helper"
require_relative "../support/library_build_helpers"

class LibraryBuildsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include LibraryBuildHelpers

  setup do
    setup_build_library
    sign_in @user
  end
  teardown { teardown_build_library }

  test "requests and polls a build for a locked historical version" do
    assert_no_difference("LibraryVersion.count") do
      post library_library_version_build_url(@library, @version), as: :json
      assert_response :accepted
      assert_equal @version.id, response.parsed_body["library_version_id"]
      assert_equal "queued", response.parsed_body["status"]
    end
    get library_library_version_build_url(@library, @version), as: :json
    assert_response :success
    assert_nil response.parsed_body["download_url"]
    get download_library_library_version_build_url(@library, @version), as: :json
    assert_response :conflict
    assert_equal "output_not_ready", response.parsed_body["error"]
  end

  test "editable source is rejected without rotating it" do
    current = @library.current_version
    assert_no_difference([ "LibraryVersion.count", "LibraryBuild.count" ]) do
      post library_library_version_build_url(@library, current), as: :json
      assert_response :conflict
      assert_equal "version_not_locked", response.parsed_body["error"]
    end
    assert_equal current.id, @library.reload.current_version_id
  end

  test "downloads the published zip even after failed regeneration" do
    build = run_export(request_export)
    original = LibraryBuilds::Storage.new(build).archive_path.binread
    build = request_export
    build.update!(status: "failed", last_error: "latest attempt failed")
    get download_library_library_version_build_url(@library, @version), as: :json
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_equal original, response.body.b
    assert_includes response.headers["Content-Disposition"], "attachment"
    get library_library_version_build_url(@library, @version), as: :json
    assert_equal "failed", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["published_generation"]
    assert response.parsed_body["download_url"]
  end

  test "versions cannot be accessed through another library" do
    other = Library.create!(name: "Other", user: @user)
    post library_library_version_build_url(other, @version), as: :json
    assert_response :not_found
  end

  test "guests and lower roles cannot build poll or download" do
    %i[guest intern_plus].each do |role|
      @user.update!(role:)
      post library_library_version_build_url(@library, @version), as: :json
      assert_response :forbidden
      get library_library_version_build_url(@library, @version), as: :json
      assert_response :forbidden
      get download_library_library_version_build_url(@library, @version), as: :json
      assert_response :forbidden
    end
    sign_out @user
    post library_library_version_build_url(@library, @version), as: :json
    assert_response :unauthorized
  end

  test "json version creation can optionally request the version just locked" do
    current_id = @library.current_version_id
    assert_difference("LibraryBuild.count", 1) do
      post library_library_versions_url(@library), params: {
        library_version: { version_number: "3.0" },
        build_previous_version: true, expected_current_version_id: current_id
      }, as: :json
      assert_response :created
    end
    payload = response.parsed_body
    assert_equal current_id, payload.dig("locked_version", "id")
    assert_equal "3.0", payload.dig("new_version", "version_number")
    assert_equal current_id, LibraryBuild.find(payload.dig("build", "id")).library_version_id
    assert_predicate @library.reload.current_version, :editable?
  end

  test "json version creation without flag does not build" do
    assert_no_difference("LibraryBuild.count") do
      post library_library_versions_url(@library), params: { library_version: { version_number: "3.0" } }, as: :json
      assert_response :created
      assert_nil response.parsed_body["build"]
    end
  end

  test "json version creation rejects invalid stale and unauthorized requests" do
    assert_no_difference([ "LibraryVersion.count", "LibraryBuild.count" ]) do
      post library_library_versions_url(@library), params: {
        library_version: { version_number: "3.0" }, build_previous_version: true, expected_current_version_id: @version.id
      }, as: :json
      assert_response :conflict
      post library_library_versions_url(@library), params: {
        library_version: { version_number: "" }, build_previous_version: true, expected_current_version_id: @library.current_version_id
      }, as: :json
      assert_response :unprocessable_content
      @user.update!(role: :intern_plus)
      post library_library_versions_url(@library), params: { library_version: { version_number: "3.0" } }, as: :json
      assert_response :forbidden
    end
  end
end
