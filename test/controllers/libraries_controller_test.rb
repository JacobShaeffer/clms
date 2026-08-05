require "test_helper"

class LibrariesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    users(:one).update!(
      name: "Library User",
      email: "library-user@example.com",
      password: "password",
      role: :organization
    )
    sign_in users(:one)

    @library = Library.create!(name: "Health Library", user: users(:one))
    @library.library_versions.create!(version_number: "2.0", user: users(:one))
    @root_folder = create_folder!(@library, name: "Health")
    @child_folder = create_folder!(@library, name: "First Aid", parent_folder: @root_folder)

    @other_library = Library.create!(name: "Science Library", user: users(:one))
    @other_root_folder = create_folder!(@other_library, name: "Science")
  end

  test "index lists each library with its current version" do
    get libraries_url

    assert_response :success
    assert_select "h1", text: "Libraries"
    assert_select "table.table.table-striped.table-hover.align-middle"
    assert_select "thead th", text: "Library name"
    assert_select "thead th", text: "Version"
    assert_select "tbody tr", count: 2

    assert_select "##{ActionView::RecordIdentifier.dom_id(@library)}[data-controller='clickable-row']" do
      assert_select "a[href='#{library_path(@library)}']", text: @library.name
      assert_select "td", text: "2.0"
    end

    assert_select "a.nav-link[href='#{libraries_path}']", text: "Library"
    assert_select "a[href='#{new_library_path}']", text: "New library", count: 0
  end

  test "authorized users can open the new library modal" do
    users(:one).update!(role: :intern_plus)

    get new_library_url, headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']" do
      assert_select ".modal-title", text: "New library"
      assert_select "form[action='#{libraries_path}'][data-turbo-frame='modal']"
      assert_select "input.form-control[name='library[name]']"
    end
  end

  test "authorized users can create a library from the modal" do
    users(:one).update!(role: :intern_plus)

    assert_difference([ "Library.count", "LibraryVersion.count" ], 1) do
      post libraries_url,
        params: { library: { name: "Agriculture Library" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :success

    library = Library.find_by!(name: "Agriculture Library")
    assert_equal users(:one), library.user
    assert_equal "1.0", library.current_version.version_number
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='update'][target='libraries'] template" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(library)}" do
        assert_select "a[href='#{library_path(library)}']", text: library.name
        assert_select "td", text: "1.0"
      end
    end
  end

  test "invalid modal submission rerenders errors" do
    users(:one).update!(role: :intern_plus)

    assert_no_difference([ "Library.count", "LibraryVersion.count" ]) do
      post libraries_url,
        params: { library: { name: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']"
    end
  end

  test "users below intern plus cannot create libraries" do
    assert_no_difference([ "Library.count", "LibraryVersion.count" ]) do
      post libraries_url, params: { library: { name: "Unauthorized Library" } }
    end

    assert_redirected_to root_url
  end

  test "index renders an empty state" do
    LibraryFolder.delete_all
    Library.update_all(current_version_id: nil)
    LibraryVersion.delete_all
    Library.delete_all

    get libraries_url

    assert_response :success
    assert_select "tbody td[colspan='2']", text: "No libraries found."
  end

  test "show lists only root folders from the selected library" do
    get library_url(@library)

    assert_response :success
    assert_select "h1", text: @library.name
    assert_select "p", text: /Version 2\.0/
    assert_select "#library-folders" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@root_folder)}", text: @root_folder.name
      assert_select "##{ActionView::RecordIdentifier.dom_id(@child_folder)}", count: 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(@other_root_folder)}", count: 0
    end
  end

  test "show renders an empty root folder state" do
    empty_library = Library.create!(name: "Empty Library", user: users(:one))

    get library_url(empty_library)

    assert_response :success
    assert_select "p", text: "No root folders found."
  end

  test "unauthenticated users are redirected to sign in" do
    sign_out users(:one)

    get libraries_url

    assert_redirected_to new_user_session_url
  end

  test "guests cannot access libraries" do
    sign_out users(:one)
    users(:two).update!(
      name: "Library Guest",
      email: "library-guest@example.com",
      password: "password",
      role: :guest
    )
    sign_in users(:two)

    get libraries_url

    assert_redirected_to root_url
  end

  private

  def create_folder!(library, name:, parent_folder: nil)
    library.library_folders.create!(
      name: name,
      parent_folder: parent_folder,
      user: users(:one),
      logo: library_assets(:one)
    )
  end
end
