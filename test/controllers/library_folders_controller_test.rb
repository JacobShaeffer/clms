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

    [ library_assets(:one), library_assets(:two) ].each do |asset|
      asset.image.attach(io: File.open(file_fixture("library_asset.png")), filename: "#{asset.id}.png", content_type: "image/png")
      asset.update!(asset_type: "Subject", language: "English")
    end

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

  test "new root folder modal asks only for a name" do
    get new_library_library_folder_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "New Folder"
    assert_select "form[action='#{library_library_folders_path(@library)}']" do
      assert_select "input[name='library_folder[name]']"
      assert_select "select[name='library_folder[logo_id]']", count: 0
      assert_select "label", text: "Library Asset", count: 0
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

  test "creates a root folder without an asset and renders an editable placeholder" do
    assert_difference("LibraryFolder.count") do
      post library_library_folders_url(@library),
        params: { library_folder: { name: "No image", logo_id: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    folder = @library.library_folders.find_by!(name: "No image")
    assert_nil folder.logo
    assert_select "##{ActionView::RecordIdentifier.dom_id(folder, :thumbnail)} a[data-turbo-frame='modal'] i.bi-image"
  end

  test "edit image modal selects the existing folder asset and preserves page context" do
    get edit_library_library_folder_url(@library, @root_folder, tab: "library"), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Choose Folder Image"
    assert_select "form[action='#{library_library_folder_path(@library, @root_folder)}'][data-turbo-frame='modal']" do
      assert_select "input[name='library_version_id'][value='#{@library.current_version_id}']"
      assert_select "input[name='tab'][value='library']"
      assert_select "input[name='library_folder[logo_id]'][value='#{@root_folder.logo_id}']"
      assert_select "input[name='library_folder[name]']", count: 0
    end
    assert_select "[aria-label='Selected Image'] img[alt='#{@root_folder.logo.display_name}']"
    assert_select "button[data-asset-id='#{@root_folder.logo_id}'][aria-pressed='true']"
    assert_select "fieldset[aria-label='Language']"
    assert_select "fieldset[aria-label='Type']", count: 0
  end

  test "updates only the image and replaces the thumbnail" do
    asset = library_assets(:two)
    asset.image.attach(io: File.open(file_fixture("library_asset.png")), filename: "thumbnail.png", content_type: "image/png")

    patch library_library_folder_url(@library, @root_folder),
      params: { library_folder: { logo_id: asset.id, name: "Unwanted rename" } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal asset, @root_folder.reload.logo
    assert_equal "Guides", @root_folder.name
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@root_folder, :thumbnail)}']" do
      assert_select "a[data-turbo-frame='modal'] img[alt='Guides Thumbnail']"
    end
  end

  test "invalid image selections keep the existing asset and rerender the selector" do
    library_assets(:two).update!(asset_type: "Banner")
    [ "", "invalid", LibraryAsset.maximum(:id) + 1, [ library_assets(:two).id ], library_assets(:two).id ].each do |logo_id|
      patch library_library_folder_url(@library, @root_folder),
        params: { library_folder: { logo_id: } },
        headers: TURBO_STREAM_HEADERS

      assert_response :unprocessable_content
      assert_equal library_assets(:one), @root_folder.reload.logo
      assert_select "turbo-stream[action='replace'][target='modal'] .alert-danger", text: /Logo is not available/
    end
  end

  test "image search and language filters cannot expose other asset types" do
    library_assets(:two).update!(asset_type: "Banner")

    get edit_library_library_folder_url(@library, @root_folder),
      params: { q: "mystring", language: "English", asset_type: "Banner" },
      headers: { "Turbo-Frame" => "image_selection_results" }

    assert_response :success
    assert_select "turbo-frame#image_selection_results button[data-asset-id]", count: 1
    assert_select "button[data-asset-id='#{library_assets(:one).id}']"
    assert_select ".modal", count: 0

    get edit_library_library_folder_url(@library, @root_folder),
      params: { language: "French" }, headers: { "Turbo-Frame" => "image_selection_results" }
    assert_select "button[data-asset-id]", count: 0
    assert_select "[role='status']", text: "No library assets match your search and filters."
  end

  test "image endpoints reject child foreign removed and historical folders" do
    child = @root_folder.child_folders.create!(name: "Child", library: @library, user: @user)
    removed = @library.library_folders.create!(name: "Removed", user: @user)
    removed.destroy!
    historical = @root_folder
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)

    [ child, @other_root, removed, historical ].each do |folder|
      sign_in @user
      get edit_library_library_folder_url(@library, folder), headers: TURBO_FRAME_HEADERS
      assert_response :not_found

      sign_in @user
      patch library_library_folder_url(@library, folder),
        params: { library_folder: { logo_id: library_assets(:two).id } }, headers: TURBO_STREAM_HEADERS
      assert_response :not_found
    end
    assert_equal library_assets(:one), historical.reload.logo
  end

  test "image endpoints reject child folders in the current version" do
    child = @root_folder.child_folders.create!(name: "Child", library: @library, user: @user)

    get edit_library_library_folder_url(@library, child), headers: TURBO_FRAME_HEADERS
    assert_response :not_found

    sign_in @user
    patch library_library_folder_url(@library, child),
      params: { library_folder: { logo_id: library_assets(:two).id } }, headers: TURBO_STREAM_HEADERS
    assert_response :not_found
    assert_nil child.reload.logo
  end

  test "users below intern plus cannot edit or update folder images" do
    @user.update!(role: :intern)

    get edit_library_library_folder_url(@library, @root_folder), headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    patch library_library_folder_url(@library, @root_folder),
      params: { library_folder: { logo_id: library_assets(:two).id } }, headers: TURBO_STREAM_HEADERS
    assert_redirected_to root_url
    assert_equal library_assets(:one), @root_folder.reload.logo
  end

  test "html image update preserves the library tab" do
    patch library_library_folder_url(@library, @root_folder),
      params: { library_folder: { logo_id: library_assets(:two).id }, tab: "library" }

    assert_redirected_to library_url(@library, tab: "library")
    assert_equal library_assets(:two), @root_folder.reload.logo
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
    assert_select "turbo-frame#modal .modal-title", text: "New Folder"
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
      assert_select ".modal-title", text: "Duplicate Items"
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

  test "rejects a parent folder that was removed" do
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ @root_folder.id ],
      content_ids: [],
      user: @user
    )

    get new_library_library_folder_url(@library, parent_folder_id: @root_folder.id),
      headers: TURBO_FRAME_HEADERS

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

  test "folder refreshes do not render trashed content" do
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    contents(:one).trash!(comment: "Hidden from folder")

    post library_library_folders_url(@library),
      params: {
        library_folder: { name: "Visible child" },
        parent_folder_id: @root_folder.id
      },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_includes response.body, "Visible child"
    assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:one), :browser)}", count: 0
  end
end
