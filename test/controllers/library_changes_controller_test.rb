require "test_helper"

class LibraryChangesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @author = users(:one)
    @author.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    @library = Library.create!(name: "Change Controller Library", user: @author)
    @folder = @library.current_version.library_folders.create!(
      library: @library,
      name: "Folder",
      user: @author,
      logo: library_assets(:one)
    )
  end

  test "an admin undoes a change" do
    change = add_content_change
    sign_in @admin

    patch undo_library_change_url(@library, change), params: { folder_id: @folder.id }

    assert_redirected_to library_changes_url(@library)
    assert_predicate change.reload, :undone?
    assert_equal @admin, change.undone_by
    refute @folder.library_folder_contents.exists?(content: contents(:one))
  end

  test "approval route is absent" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/libraries/#{@library.id}/changes/1/approve",
        method: :patch
      )
    end
  end

  test "history includes applied undone and locked-version changes" do
    change = add_content_change
    LibraryChanges::Undo.call(change:, user: @author)
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @admin)
    sign_in @admin

    get library_changes_url(@library)

    assert_response :success
    assert_select "h1", text: "Change history"
    assert_select "section[aria-label='Version 1.0 changes']" do
      assert_select ".library-change-undone[data-change-id='#{change.id}'] a", text: /#{Regexp.escape(change.display_label)}.*Add content.*Undone/
    end
    assert_select "a[data-turbo-frame='modal'][href='#{library_change_path(@library, change)}']"
    assert_select "input[type='submit'][value='Undo']", count: 0
  end

  test "details show the author and dependent edits with explicit confirmation IDs" do
    first = add_content_change
    second = remove_content_change
    sign_in @admin

    get library_change_url(@library, first), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Change details"
    assert_select "dd", text: @author.name
    assert_select "dd", text: "Add content"
    assert_select "[data-library-change-details][data-change-id='#{first.id}'][data-dependent-change-ids='[#{second.id}]']"
    assert_select ".alert-warning", text: /will also undo all 1 dependent edits/
    assert_select "ul[aria-label='Dependent edits to undo'] li", text: /Remove content/
    assert_select "input[name='dependent_change_ids[]'][value='#{second.id}']"
    assert_select "input[type='submit'][value='Undo']"
  end

  test "submitting the reviewed chain undoes it and returns to history" do
    first = add_content_change
    second = remove_content_change
    sign_in @admin

    patch undo_library_change_url(@library, first), params: { cascade: "1", dependent_change_ids: [ second.id ] }

    assert_redirected_to library_changes_url(@library)
    assert_predicate first.reload, :undone?
    assert_predicate second.reload, :undone?
    refute @folder.library_folder_contents.exists?(content: contents(:one))
  end

  test "a stale preview redirects to history without undoing anything" do
    first = add_content_change
    second = remove_content_change
    sign_in @admin

    patch undo_library_change_url(@library, first), params: { cascade: "1" }

    assert_redirected_to library_changes_url(@library)
    assert_match(/Dependent edits have changed/, flash[:alert])
    refute_predicate first.reload, :undone?
    refute_predicate second.reload, :undone?
  end

  test "admins can review mixed-author chains" do
    first = add_content_change
    second = remove_content_change(user: @admin)
    sign_in @admin
    get library_change_url(@library, first), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "input[name='dependent_change_ids[]'][value='#{second.id}']"
    assert_select "input[type='submit'][value='Undo']"
  end

  test "nonadmins cannot access history" do
    sign_in @author

    get library_changes_url(@library)

    assert_redirected_to root_url
    assert_equal "You are not authorized to perform that action.", flash[:alert]
  end

  test "nonadmins cannot access change details directly or through a modal" do
    change = add_content_change
    sign_in @author

    [ {}, { "Turbo-Frame" => "modal" } ].each do |headers|
      get library_change_url(@library, change), headers: headers

      assert_redirected_to root_url
    end
  end

  test "nonadmins cannot submit undo even for their own edits" do
    change = add_content_change
    sign_in @author

    [ {}, { cascade: "1" } ].each do |parameters|
      patch undo_library_change_url(@library, change), params: parameters

      assert_redirected_to root_url
      refute_predicate change.reload, :undone?
      assert @folder.library_folder_contents.exists?(content: contents(:one))
    end
  end

  test "anonymous visitors must sign in to access history" do
    get library_changes_url(@library)

    assert_redirected_to new_user_session_url
  end

  test "locked changes have readable details but cannot be undone" do
    change = add_content_change
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @admin)
    sign_in @admin

    get library_change_url(@library, change), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "p", text: "Changes in previous versions are read only."
    assert_select "input[type='submit'][value='Undo']", count: 0

    patch undo_library_change_url(@library, change), params: { cascade: "1" }
    assert_redirected_to library_changes_url(@library)
    assert_match(/editable current version/, flash[:alert])
    refute_predicate change.reload, :undone?
  end

  test "a change cannot be read through another library" do
    change = add_content_change
    other_library = Library.create!(name: "Other Library", user: @author)
    sign_in @admin

    get library_change_url(other_library, change)

    assert_response :not_found
  end

  test "history has an empty state" do
    sign_in @admin
    get library_changes_url(@library)

    assert_response :success
    assert_select "p", text: "No changes to show for this library."
  end

  test "trashed content disappears from history and returns when restored" do
    content = contents(:one)
    content.update_columns(title: "Hidden change content", display_title: "Hidden change content")
    first = add_content_change
    second = remove_content_change
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: @folder.id, content_ids: [ contents(:two).id ], user: @author
    )
    visible_change = @library.current_version.library_changes.last
    sign_in @admin

    assert_no_difference("LibraryChange.count") do
      content.trash!
      get library_changes_url(@library)
    end

    assert_response :success
    assert_select ".library-change-row", count: 1
    assert_select ".library-change-row[data-change-id='#{visible_change.id}']"
    refute_includes response.body, content.title
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    [ {}, { "Turbo-Frame" => "modal" } ].each do |headers|
      get library_change_url(@library, first), headers: headers
      assert_response :not_found
    end

    content.restore!
    get library_changes_url(@library)

    assert_select ".library-change-row", count: 3
    [ first, second ].each { |change| assert_select ".library-change-row[data-change-id='#{change.id}']" }
  end

  test "trashed content is also hidden in locked-version history" do
    change = add_content_change
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @admin)
    contents(:one).trash!
    sign_in @admin

    get library_changes_url(@library)

    assert_response :success
    assert_select ".library-change-row", count: 0
    assert_select "p", text: "No changes to show for this library."
    assert LibraryChange.exists?(change.id)
  end

  test "folder details hide trashed content while undo still reverses its dependent edits" do
    content = contents(:one)
    content.update_columns(title: "Hidden change content", display_title: "Hidden change content")
    folder_change = LibraryChanges::Recorder.call(
      library_version: @library.current_version, user: @author, action_type: :add_folder,
      details: { folder_id: @folder.id, parent_folder_id: nil, logo_id: @folder.logo_id },
      targets: [ {
        target_kind: :folder, target_id: @folder.id, folder_id: @folder.id,
        resource_key: LibraryChanges::Recorder.folder_key(@folder),
        effect: :new, direct: true, label: @folder.name
      } ]
    )
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: @folder.id,
      content_ids: [ content.id, contents(:two).id ], user: @author
    )
    LibraryFolderOperations::Remove.call(
      library: @library, source_folder_id: nil, folder_ids: [ @folder.id ], content_ids: [], user: @author
    )
    removal = @library.current_version.library_changes.remove_folder.last
    dependent_ids = @library.current_version.library_changes.where.not(id: folder_change.id).ordered.ids
    content.trash!
    sign_in @admin

    get library_change_url(@library, removal), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    refute_includes response.body, content.title
    assert_includes response.body, contents(:two).title

    get library_change_url(@library, folder_change), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    refute_includes response.body, content.title
    assert_select "ul[aria-label='Dependent edits to undo'] li", count: 2
    assert_select ".alert-warning", text: /undo all 3 dependent edits/
    assert_select "p", text: "1 additional dependent edit involving content in Trash will also be undone."
    assert_select "input[name='dependent_change_ids[]']", count: 3

    patch undo_library_change_url(@library, folder_change), params: { cascade: "1", dependent_change_ids: dependent_ids }

    assert_redirected_to library_changes_url(@library)
    assert @library.current_version.library_changes.all?(&:undone?)
    refute LibraryFolder.exists?(@folder.id)
    assert_predicate content.reload, :trashed?
  end

  test "a blocked undo redirects with an explanation" do
    first = add_content_change
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: @folder.id,
      folder_ids: [],
      content_ids: [ contents(:one).id ],
      user: @author
    )
    second = @library.current_version.library_changes.remove_content.last
    sign_in @admin

    patch undo_library_change_url(@library, first)

    assert_redirected_to library_changes_url(@library)
    assert_match(/Undo #{Regexp.escape(second.display_label)} before/, flash[:alert])
    refute_predicate first.reload, :undone?
  end

  test "undoing a new folder returns to history" do
    child = @library.current_version.library_folders.create!(
      library: @library,
      name: "New Child",
      parent_folder: @folder,
      user: @author
    )
    change = LibraryChanges::Recorder.call(
      library_version: @library.current_version,
      user: @author,
      action_type: :add_folder,
      details: {
        folder_id: child.id,
        parent_folder_id: @folder.id,
        logo_id: nil
      },
      targets: [ {
        target_kind: :folder,
        target_id: child.id,
        folder_id: child.id,
        resource_key: LibraryChanges::Recorder.folder_key(child),
        effect: :new,
        direct: true,
        label: child.name
      } ]
    )
    sign_in @admin

    patch undo_library_change_url(@library, change), params: { folder_id: child.id }

    assert_redirected_to library_changes_url(@library)
    refute LibraryFolder.exists?(child.id)
  end

  private

  def remove_content_change(user: @author)
    LibraryFolderOperations::Remove.call(
      library: @library, source_folder_id: @folder.id,
      folder_ids: [], content_ids: [ contents(:one).id ], user:
    )
    @library.current_version.library_changes.remove_content.last
  end

  def add_content_change
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @folder.id,
      content_ids: [ contents(:one).id ],
      user: @author
    )
    @library.current_version.library_changes.add_content.last
  end
end
