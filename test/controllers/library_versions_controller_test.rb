require "test_helper"

class LibraryVersionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    @admin = users(:one)
    @admin.update!(
      name: "Version Admin",
      email: "version-admin@example.com",
      password: "password",
      role: :admin
    )
    sign_in @admin

    @library = Library.create!(name: "Versioned Library", user: @admin)
  end

  test "admin opens the new version modal" do
    get new_library_library_version_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']" do
      assert_select ".modal-title", text: "New version"
      assert_select "form[action='#{library_library_versions_path(@library)}'][data-turbo-frame='_top']" do
        assert_select "input.form-control[name='library_version[version_number]'][required]"
        assert_select "input[type='submit'][value='Create version']"
      end
    end
  end

  test "admin creates a version and reloads the base library page" do
    assert_difference("LibraryVersion.count", 1) do
      post library_library_versions_url(@library),
        params: { library_version: { version_number: "2.0" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_redirected_to library_url(@library)
    assert_equal "2.0", @library.reload.current_version.version_number
    assert_equal @admin, @library.current_version.user
    assert_equal "Library version 2.0 was successfully created.", flash[:notice]
  end

  test "version creation drops a stale open-folder URL" do
    folder = @library.current_version.library_folders.create!(
      library: @library,
      name: "Open folder",
      user: @admin,
      logo: library_assets(:one)
    )

    post library_library_versions_url(@library),
      params: {
        library_version: { version_number: "2.0" },
        folder_id: folder.id
      },
      headers: TURBO_STREAM_HEADERS

    assert_redirected_to library_url(@library)
    refute_includes response.location, "folder_id"
  end

  test "html creation redirects to the current library" do
    assert_difference("LibraryVersion.count", 1) do
      post library_library_versions_url(@library),
        params: { library_version: { version_number: "2.0" } }
    end

    assert_redirected_to library_url(@library)
  end

  test "invalid version keeps validation errors in the modal" do
    assert_no_difference("LibraryVersion.count") do
      post library_library_versions_url(@library),
        params: { library_version: { version_number: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']", text: /Version number can't be blank/
      assert_select "input[name='library_version[version_number]'][value='']"
    end
  end

  test "duplicate version keeps the submitted number in the modal" do
    assert_no_difference("LibraryVersion.count") do
      post library_library_versions_url(@library),
        params: { library_version: { version_number: "1.0" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']", text: /Version number has already been taken/
      assert_select "input[name='library_version[version_number]'][value='1.0']"
    end
  end

  test "non-admin cannot open or create a version" do
    @admin.update!(role: :intern_plus)

    get new_library_library_version_url(@library), headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    assert_no_difference("LibraryVersion.count") do
      post library_library_versions_url(@library),
        params: { library_version: { version_number: "2.0" } },
        headers: TURBO_STREAM_HEADERS
    end
    assert_redirected_to root_url
  end

  test "only admins see the new version button" do
    get library_url(@library)

    assert_response :success
    assert_select "a[href='#{new_library_library_version_path(@library)}'][data-turbo-frame='modal']",
      text: "New version"

    @admin.update!(role: :intern_plus)
    get library_url(@library)

    assert_response :success
    assert_select "a[href='#{new_library_library_version_path(@library)}']", text: "New version", count: 0
  end

  test "unauthenticated users are redirected to sign in" do
    sign_out @admin

    get new_library_library_version_url(@library)

    assert_redirected_to new_user_session_url
  end
end
