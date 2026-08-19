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
    assert_select "turbo-frame#modal .modal-title", text: "Add folder"
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

  test "rejects foreign and malformed parents" do
    get new_library_library_folder_url(@library, parent_folder_id: @other_root.id), headers: TURBO_FRAME_HEADERS
    assert_response :not_found

    sign_in @user
    get new_library_library_folder_url(@library),
      params: { parent_folder_id: [ @root_folder.id ] },
      headers: TURBO_FRAME_HEADERS
    assert_response :not_found
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
