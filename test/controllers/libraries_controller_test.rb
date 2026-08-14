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
    users(:one).content_table_preferences.delete_all
    users(:one).active_shelves.delete_all

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
    assert_select "#library-folder-browser-items" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@root_folder, :browser)}", text: /#{@root_folder.name}/
      assert_select "##{ActionView::RecordIdentifier.dom_id(@child_folder, :browser)}", count: 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(@other_root_folder, :browser)}", count: 0
    end
  end

  test "show renders an empty root folder state" do
    empty_library = Library.create!(name: "Empty Library", user: users(:one))

    get library_url(empty_library)

    assert_response :success
    assert_select "p", text: "No root folders found."
  end

  test "folder browser opens a folder and shows direct children content and breadcrumbs" do
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @child_folder, content: contents(:two))

    get library_url(@library, folder_id: @root_folder.id)

    assert_response :success
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}"
    assert_select "nav[aria-label='Library folder breadcrumb'] .breadcrumb-item", count: 2
    assert_select ".breadcrumb-item.active", text: @root_folder.name
    assert_select "##{ActionView::RecordIdentifier.dom_id(@child_folder, :browser)}", text: /#{@child_folder.name}/
    assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:one), :browser)}", text: /#{contents(:one).title}/
    assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:two), :browser)}", count: 0

    get library_url(@library, folder_id: @child_folder.id)

    assert_response :success
    assert_select ".breadcrumb-item", count: 3
    assert_select ".breadcrumb-item a", text: @root_folder.name
    assert_select ".breadcrumb-item.active", text: @child_folder.name
    assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:two), :browser)}", text: /#{contents(:two).title}/
  end

  test "folder browser rejects a folder from another library" do
    get library_url(@library, folder_id: @other_root_folder.id)

    assert_response :not_found
  end

  test "folder and shelf navigation reject malformed identifiers" do
    get library_url(@library), params: { folder_id: [ @root_folder.id ] }
    assert_response :not_found

    sign_in users(:one)
    get shelf_contents_table_library_url(@library), params: { shelf_id: [ shelves(:one).id ] }
    assert_response :not_found
  end

  test "all content is the default tab and renders library folder placements with independent tooltips" do
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @child_folder, content: contents(:one))

    get library_url(@library)

    assert_response :success
    assert_select ".nav-tabs .nav-link.active", text: "All Content"
    assert_select "turbo-frame#library_#{@library.id}_all_contents_table"
    assert_select "th", text: "Library folders"
    row_id = "library-#{@library.id}-all-contents-#{ActionView::RecordIdentifier.dom_id(contents(:one)).dasherize}"
    assert_select "tr##{row_id}" do
      assert_select "[data-controller='tooltip']", count: 2
      assert_select "[title='Health Library / Health']", text: "Health"
      assert_select "[title='Health Library / Health / First Aid']", text: "First Aid"
    end
    other_row_id = "library-#{@library.id}-all-contents-#{ActionView::RecordIdentifier.dom_id(contents(:two)).dasherize}"
    assert_select "tr##{other_row_id} [data-controller='tooltip']", count: 0
  end

  test "library content tab lists each placed content once and excludes other content" do
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @child_folder, content: contents(:one))

    get library_url(@library, tab: "library")

    assert_response :success
    assert_select ".nav-tabs .nav-link.active", text: "Library Content"
    assert_select "turbo-frame#library_#{@library.id}_library_contents_table tbody tr", count: 1
    assert_select "tbody", text: /#{contents(:one).title}/
  end

  test "shelves tab lists active shelves in saved order and opens a table without search or filters" do
    first_shelf = users(:one).shelves.create!(name: "First Active")
    second_shelf = users(:one).shelves.create!(name: "Second Active")
    first_shelf.contents << contents(:one)
    second_shelf.contents << contents(:two)
    ActiveShelf.activate!(user: users(:one), shelf: second_shelf)
    ActiveShelf.activate!(user: users(:one), shelf: first_shelf)

    get library_url(@library, tab: "shelves", shelf_id: first_shelf.id)

    assert_response :success
    assert_select ".nav-tabs .nav-link.active", text: "Shelves"
    assert_select "#library-active-shelves a:nth-child(1)", text: second_shelf.name
    assert_select "#library-active-shelves a:nth-child(2).active", text: first_shelf.name
    assert_select "turbo-frame#library_#{@library.id}_shelf_#{first_shelf.id}_contents_table"
    assert_select "input[name='q']", count: 0
    assert_select "button", text: "Advanced Filters", count: 0
    assert_select ".offcanvas", count: 0
    assert_select "th", text: "Library folders"
    assert_select "tbody", text: /#{contents(:one).title}/
  end

  test "shelf table ignores submitted search and filters and requires an active shelf" do
    shelf = users(:one).shelves.create!(name: "Active")
    shelf.contents << contents(:one)
    ActiveShelf.activate!(user: users(:one), shelf:)

    get shelf_contents_table_library_url(
      @library,
      shelf_id: shelf.id,
      q: "does not match",
      per_page: 20,
      filters: { title: { value: "does not match" } }
    )

    assert_response :success
    assert_select "tbody", text: /#{contents(:one).title}/
    preference = users(:one).content_table_preferences.find_by!(
      table_key: "libraries.#{@library.id}.shelves.#{shelf.id}.contents"
    )
    assert_equal "", preference.state.fetch("q")
    assert_empty preference.state.fetch("filters")

    inactive_shelf = users(:one).shelves.create!(name: "Inactive")
    get shelf_contents_table_library_url(@library, shelf_id: inactive_shelf.id)
    assert_response :not_found
  end

  test "library table preferences are isolated and reset per tab" do
    get all_contents_table_library_url(@library, q: "First")
    get library_contents_table_library_url(@library, q: "Second")

    all_preference = users(:one).content_table_preferences.find_by!(
      table_key: "libraries.#{@library.id}.all_contents"
    )
    library_preference = users(:one).content_table_preferences.find_by!(
      table_key: "libraries.#{@library.id}.library_contents"
    )
    assert_equal "First", all_preference.state.fetch("q")
    assert_equal "Second", library_preference.state.fetch("q")

    delete reset_all_contents_table_library_url(@library)

    assert_redirected_to library_url(@library, tab: "all")
    refute ContentTablePreference.exists?(all_preference.id)
    assert ContentTablePreference.exists?(library_preference.id)
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
