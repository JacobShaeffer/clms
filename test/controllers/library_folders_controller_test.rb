require "test_helper"

class LibraryFoldersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    @user = users(:one)
    @user.update!(
      name: "Folder Editor",
      email: "folder-editor@example.com",
      password: "password",
      role: :intern_plus
    )
    sign_in @user

    @library = Library.create!(name: "Health Library", user: @user)
    @root_folder = @library.library_folders.create!(
      name: "Guides",
      user: @user,
      logo: library_assets(:one)
    )
    @other_library = Library.create!(name: "Other Library", user: @user)
    @other_root = @other_library.library_folders.create!(
      name: "Other Root",
      user: @user,
      logo: library_assets(:one)
    )
  end

  test "new root folder modal includes a library asset field" do
    get new_library_library_folder_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "New folder"
    assert_select "form[action='#{library_library_folders_path(@library)}']" do
      assert_select "input[name='library_folder[name]']"
      assert_select "select[name='library_folder[logo_id]'][required]"
      assert_select "label", text: "Library asset"
    end
  end

  test "new child folder modal omits the library asset field" do
    get new_library_library_folder_url(@library, parent_folder_id: @root_folder.id),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "input[name='parent_folder_id'][value='#{@root_folder.id}']"
    assert_select "select[name='library_folder[logo_id]']", count: 0
  end

  test "creates a root folder with an asset and refreshes the root browser" do
    assert_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "Nutrition", logo_id: library_assets(:one).id },
          tab: "all"
        },
        headers: TURBO_STREAM_HEADERS
    end

    folder = @library.library_folders.find_by!(name: "Nutrition")
    assert_nil folder.parent_folder
    assert_equal library_assets(:one), folder.logo
    assert_equal @user, folder.user
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}']",
      text: /Nutrition/
  end

  test "creates a child folder without an asset and refreshes its parent" do
    assert_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "First Aid", logo_id: library_assets(:one).id },
          parent_folder_id: @root_folder.id,
          tab: "library"
        },
        headers: TURBO_STREAM_HEADERS
    end

    folder = @library.library_folders.find_by!(name: "First Aid")
    assert_equal @root_folder, folder.parent_folder
    assert_nil folder.logo
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}']",
      text: /First Aid/
  end

  test "invalid folder rerenders the modal" do
    assert_no_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: { library_folder: { name: "", logo_id: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] .alert-danger"
  end

  test "new folder opened from a destination picker preserves its operation context" do
    selected_folder = @library.library_folders.create!(
      name: "Selected",
      parent_folder: @root_folder,
      user: @user
    )
    destination = @library.library_folders.create!(
      name: "Destination",
      user: @user,
      logo: library_assets(:one)
    )

    get new_library_library_folder_url(
      @library,
      parent_folder_id: destination.id,
      picker_operation: "move",
      source_folder_id: @root_folder.id,
      folder_ids: [ selected_folder.id ],
      tab: "all"
    ), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "New folder"
    assert_select "input[name='picker_operation'][value='move']"
    assert_select "input[name='source_folder_id'][value='#{@root_folder.id}']"
    assert_select "input[name='folder_ids[]'][value='#{selected_folder.id}']"
    assert_select "a.btn.btn-secondary[data-turbo-frame='modal']", text: "Back"
    assert_select ".modal-footer button[data-bs-dismiss='modal']", count: 0
  end

  test "creating a picker folder returns to the picker inside the new destination" do
    selected_folder = @library.library_folders.create!(
      name: "Selected",
      parent_folder: @root_folder,
      user: @user
    )
    destination = @library.library_folders.create!(
      name: "Destination",
      user: @user,
      logo: library_assets(:one)
    )

    assert_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "New Destination" },
          parent_folder_id: destination.id,
          picker_operation: "duplicate",
          picker_folder_id: destination.id,
          source_folder_id: @root_folder.id,
          folder_ids: [ selected_folder.id ],
          tab: "all"
        },
        headers: TURBO_STREAM_HEADERS
    end

    new_destination = destination.child_folders.find_by!(name: "New Destination")
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}']"
    assert_select "turbo-stream[action='replace'][target='modal'] template" do
      assert_select ".modal-title", text: "Duplicate items"
      assert_select ".breadcrumb-item.active", text: new_destination.name
      assert_select "input[type='hidden'][name='destination_folder_id']" \
        "[value='#{new_destination.id}']:not([disabled])"
      assert_select "button", text: "Duplicate Here", disabled: false
    end
  end

  test "invalid picker folder retains the pending selection" do
    selected_folder = @library.library_folders.create!(
      name: "Selected",
      parent_folder: @root_folder,
      user: @user
    )

    assert_no_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "" },
          parent_folder_id: @root_folder.id,
          picker_operation: "move",
          picker_folder_id: @root_folder.id,
          source_folder_id: @root_folder.id,
          folder_ids: [ selected_folder.id ],
          tab: "all"
        },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template" do
      assert_select ".alert-danger"
      assert_select "input[name='picker_operation'][value='move']"
      assert_select "input[name='folder_ids[]'][value='#{selected_folder.id}']"
      assert_select "a", text: "Back"
    end
  end

  test "rejects foreign and malformed parents" do
    get new_library_library_folder_url(@library, parent_folder_id: @other_root.id), headers: TURBO_FRAME_HEADERS
    assert_response :not_found

    sign_in @user
    get new_library_library_folder_url(@library),
      params: { parent_folder_id: [ @root_folder.id ] },
      headers: TURBO_FRAME_HEADERS
    assert_response :not_found
  end

  test "rejects a parent folder from a locked version" do
    locked_root = @root_folder
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)

    assert_no_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "Stale child" },
          parent_folder_id: locked_root.id
        },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :not_found
  end

  test "rejects a new folder request for a non-current version" do
    historical_version = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)

    assert_no_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: {
          library_folder: { name: "Historical folder", logo_id: library_assets(:one).id },
          library_version_id: historical_version.id
        },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select ".alert-danger", text: "Only the current library version can be changed."
  end

  test "users below intern plus cannot create folders" do
    @user.update!(role: :intern)

    assert_no_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: { library_folder: { name: "Unauthorized", logo_id: library_assets(:one).id } }
    end

    assert_redirected_to root_url
  end
end
