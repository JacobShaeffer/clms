require "test_helper"

class LibrariesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze
  PLACEMENT_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

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
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: users(:one))
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
    LibraryFolderContent.delete_all
    LibraryVersionContent.delete_all
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

  test "intern plus users see folder actions and the root placement button is enabled" do
    users(:one).update!(role: :intern_plus)

    get library_url(@library)

    assert_select "a[data-turbo-frame='modal']", text: "New Folder"
    assert_select "input[type='submit'][value='Add to Active Folder']:not([disabled])"

    get library_url(@library, folder_id: @root_folder.id)

    assert_select "input[type='submit'][value='Add to Active Folder']:not([disabled])"
    assert_select "input[name='folder_id'][value='#{@root_folder.id}']"
    assert_select "tbody input[name='content_ids[]'][form='library_#{@library.id}_all_contents_table_add_to_active_folder_form']"
  end

  test "add to active folder appears above each rendered tab table" do
    users(:one).update!(role: :intern_plus)
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    shelf = users(:one).shelves.create!(name: "Active Shelf")
    shelf.contents << contents(:one)
    ActiveShelf.activate!(user: users(:one), shelf:)

    [
      { tab: "all", frame_id: "library_#{@library.id}_all_contents_table" },
      { tab: "library", frame_id: "library_#{@library.id}_library_contents_table" },
      { tab: "shelves", shelf_id: shelf.id, frame_id: "library_#{@library.id}_shelf_#{shelf.id}_contents_table" }
    ].each do |context|
      get library_url(@library, folder_id: @root_folder.id, **context.except(:frame_id))

      assert_response :success
      assert_select "form##{context[:frame_id]}_add_to_active_folder_form" do
        assert_select "input[type='submit'][value='Add to Active Folder']:not([disabled])"
      end
    end
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

  test "folder browser marks files changed since the previous version and resets on the next version" do
    content = create_content_with_file!(bytes: "original library file")
    LibraryFolderContent.create!(library_folder: @root_folder, content:)
    LibraryVersions::Create.call(library: @library, version_number: "3.0", user: users(:one))
    current_root = @library.reload.current_version.library_folders.find_by!(name: @root_folder.name)

    get library_url(@library, folder_id: current_root.id)
    assert_select "##{ActionView::RecordIdentifier.dom_id(content, :browser)} .badge",
      text: "File changed",
      count: 0

    content.update!(display_title: "Updated display title")
    get library_url(@library, folder_id: current_root.id)
    assert_select "##{ActionView::RecordIdentifier.dom_id(content, :browser)} .badge",
      text: "File changed",
      count: 0

    content.file.attach(
      io: StringIO.new("changed library file"),
      filename: "changed-library-file.png",
      content_type: "image/png"
    )
    get library_url(@library, folder_id: current_root.id)
    assert_select "##{ActionView::RecordIdentifier.dom_id(content, :browser)} .badge",
      text: "File changed",
      count: 1

    LibraryVersions::Create.call(library: @library, version_number: "4.0", user: users(:one))
    next_root = @library.reload.current_version.library_folders.find_by!(name: @root_folder.name)
    get library_url(@library, folder_id: next_root.id)
    assert_select "##{ActionView::RecordIdentifier.dom_id(content, :browser)} .badge",
      text: "File changed",
      count: 0
  end

  test "folder browser does not mark changed files for content absent from the previous version" do
    content = create_content_with_file!(bytes: "new content original file")
    LibraryFolderContent.create!(library_folder: @root_folder, content:)
    content.file.attach(
      io: StringIO.new("new content changed file"),
      filename: "new-content-changed-file.png",
      content_type: "image/png"
    )

    get library_url(@library, folder_id: @root_folder.id)

    assert_select "##{ActionView::RecordIdentifier.dom_id(content, :browser)} .badge",
      text: "File changed",
      count: 0
  end

  test "folder browser renders accessible selection checkboxes for direct folders and content" do
    users(:one).update!(role: :intern_plus)
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @child_folder, content: contents(:two))

    get library_url(@library, folder_id: @root_folder.id)

    assert_response :success
    assert_select "section[data-controller='library-folder-selection']" \
      "[data-action*='change->library-folder-selection#update']" do
      assert_select "[data-library-folder-selection-target='actions'].d-none[hidden]" do
        assert_select "button.btn.btn-warning[type='submit'][formaction='#{move_library_folder_selection_path(@library)}']",
          text: "Move"
        assert_select "button.btn.btn-danger[type='submit']" \
          "[formaction='#{remove_confirmation_library_folder_selection_path(@library)}']",
          text: "Remove"
        assert_select "button.btn.btn-secondary[type='submit']" \
          "[formaction='#{duplicate_library_folder_selection_path(@library)}']",
          text: "Duplicate"
      end

      assert_select "#library-folder-browser-items" do
        assert_select "##{ActionView::RecordIdentifier.dom_id(@child_folder, :browser)}" do
          assert_select "input.form-check-input[type='checkbox'][name='folder_ids[]'][value='#{@child_folder.id}']" \
            "[id='#{ActionView::RecordIdentifier.dom_id(@child_folder, :browser_selection)}']" \
            "[aria-label='Select folder #{@child_folder.name}']" \
            "[data-library-folder-selection-target='item']",
            count: 1
          assert_select "a[href='#{library_path(@library, folder_id: @child_folder.id, tab: "all")}']",
            text: @child_folder.name
        end
        assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:one), :browser)}" do
          assert_select "input.form-check-input[type='checkbox'][name='content_ids[]'][value='#{contents(:one).id}']" \
            "[id='#{ActionView::RecordIdentifier.dom_id(contents(:one), :browser_selection)}']" \
            "[aria-label='Select content #{contents(:one).title}']" \
            "[data-library-folder-selection-target='item']",
            count: 1
        end
        assert_select "input[type='checkbox'][checked]", count: 0
      end
    end

    assert_select "##{ActionView::RecordIdentifier.dom_id(contents(:two), :browser)}", count: 0
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
    assert_select "[data-controller~='library-content-selection']"
    assert_select "[data-library-content-selection-scope='all'][data-content-table-selection-preserve-before-cache-value='true']"
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
    assert_select ".nav-tabs .nav-link.active", text: "Current Library"
    assert_select "turbo-frame#library_#{@library.id}_library_contents_table tbody tr", count: 1
    assert_select "tbody", text: /#{contents(:one).title}/
  end

  test "library content and folder tooltips exclude placements from locked versions" do
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    locked_version = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "3.0", user: users(:one))
    current_root = @library.reload.current_version.library_folders.find_by!(name: @root_folder.name)
    current_root.library_folder_contents.find_by!(content: contents(:one)).destroy!

    assert locked_version.library_folder_contents.exists?(content: contents(:one))

    get library_url(@library, tab: "library")
    assert_select "tbody", text: /#{Regexp.escape(contents(:one).title)}/, count: 0

    get library_url(@library, tab: "all")
    row_id = "library-#{@library.id}-all-contents-#{ActionView::RecordIdentifier.dom_id(contents(:one)).dasherize}"
    assert_select "tr##{row_id} [title='Health Library / Health']", count: 0
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

  test "tab links preserve the selected shelf only while it remains in the library URL" do
    shelf = users(:one).shelves.create!(name: "Selected Shelf")
    ActiveShelf.activate!(user: users(:one), shelf:)

    get library_url(@library, tab: "all", shelf_id: shelf.id)

    assert_response :success
    assert_select ".nav-tabs a[href='#{library_path(@library, tab: "shelves", shelf_id: shelf.id)}']",
      text: "Shelves"

    get library_url(@library)

    assert_response :success
    assert_select ".nav-tabs a[href='#{library_path(@library, tab: "shelves")}']", text: "Shelves"
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

  test "add to active folder creates missing placements and keeps existing placements" do
    users(:one).update!(role: :intern_plus)
    LibraryFolderContent.create!(library_folder: @root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @child_folder, content: contents(:one))

    assert_difference("LibraryFolderContent.count", 1) do
      post add_to_active_folder_library_url(@library),
        params: {
          folder_id: @root_folder.id,
          tab: "all",
          content_ids: [ contents(:one).id, contents(:two).id ]
        },
        headers: PLACEMENT_HEADERS
    end

    assert_equal [ contents(:one).id, contents(:two).id ].sort, @root_folder.contents.ids.sort
    assert_includes @child_folder.contents, contents(:one)
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}']",
      text: /#{Regexp.escape(contents(:two).title)}/
    assert_select "turbo-stream[action='replace'][target='library_#{@library.id}_all_contents_table']"
    assert_select "turbo-stream[action='update'][target='library-add-to-active-folder-status']",
      text: /Existing placements were skipped/

    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: {
          folder_id: @root_folder.id,
          tab: "all",
          content_ids: [ contents(:one).id, contents(:two).id ]
        },
        headers: PLACEMENT_HEADERS
    end
    assert_select "turbo-stream[target='library-add-to-active-folder-status']",
      text: /already in the active folder/
  end

  test "add to active folder rejects root empty stale foreign and malformed selections" do
    users(:one).update!(role: :intern_plus)

    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: { tab: "all", content_ids: [ contents(:one).id ] },
        headers: PLACEMENT_HEADERS
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[target='library-add-to-active-folder-status']", text: /Open a folder/

    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: { folder_id: @root_folder.id, tab: "all", content_ids: [] },
        headers: PLACEMENT_HEADERS
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[target='library-add-to-active-folder-status']", text: /Select at least one/

    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: { folder_id: @root_folder.id, tab: "all", content_ids: [ -999 ] },
        headers: PLACEMENT_HEADERS
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[target='library-add-to-active-folder-status']", text: /unavailable/

    post add_to_active_folder_library_url(@library),
      params: { folder_id: @other_root_folder.id, tab: "all", content_ids: [ contents(:one).id ] },
      headers: PLACEMENT_HEADERS
    assert_response :not_found

    post add_to_active_folder_library_url(@library),
      params: { folder_id: [ @root_folder.id ], tab: "all", content_ids: [ contents(:one).id ] },
      headers: PLACEMENT_HEADERS
    assert_response :not_found
  end

  test "users below intern plus cannot add content to a folder" do
    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: { folder_id: @root_folder.id, tab: "all", content_ids: [ contents(:one).id ] }
    end

    assert_redirected_to root_url
  end

  test "shelf placement response requires the selected shelf to remain active" do
    users(:one).update!(role: :intern_plus)
    inactive_shelf = users(:one).shelves.create!(name: "Inactive")

    assert_no_difference("LibraryFolderContent.count") do
      post add_to_active_folder_library_url(@library),
        params: {
          folder_id: @root_folder.id,
          tab: "shelves",
          shelf_id: inactive_shelf.id,
          content_ids: [ contents(:one).id ]
        },
        headers: PLACEMENT_HEADERS
    end

    assert_response :not_found
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
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end

  def create_content_with_file!(bytes:)
    Content.new(
      title: "Versioned content #{SecureRandom.hex(4)}",
      display_title: "Versioned content",
      description: "Content used to verify library file changes.",
      user: users(:one)
    ).tap do |content|
      content.file.attach(
        io: StringIO.new(bytes),
        filename: "library-file-#{SecureRandom.hex(4)}.png",
        content_type: "image/png"
      )
      content.save!
    end
  end
end
