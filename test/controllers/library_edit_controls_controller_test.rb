require "test_helper"

class LibraryEditControlsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(role: :intern_plus)
    sign_in @user
    @library = Library.create!(name: "Controls Library", user: @user)
    @root = @library.current_version.library_folders.create!(name: "Root", user: @user, logo: library_assets(:one))
    @page_session = SecureRandom.uuid
    @headers = { LibraryChanges::PageReceipt::SESSION_HEADER => @page_session, "Accept" => "application/json" }
  end

  test "new folder response issues a receipt and undo falls back from the removed open folder" do
    post library_library_folders_url(@library), params: { library_folder: { name: "Child" }, parent_folder_id: @root.id },
      headers: @headers.merge("Accept" => "text/vnd.turbo-stream.html")
    assert_response :success
    receipt = response.headers[LibraryChanges::PageReceipt::HEADER]
    assert receipt
    child = @root.child_folders.find_by!(name: "Child")
    changes = LibraryChanges::PageReceipt.resolve(receipt:, user: @user, library: @library, page_session: @page_session)
    assert_equal [ child.id ], changes.map { |change| change.details["folder_id"] }

    patch undo_library_edit_controls_url(@library), params: { receipt:, context: { folder_id: child.id, tab: "library" } }, headers: @headers, as: :json
    assert_response :success
    assert_equal library_path(@library, folder_id: @root.id, tab: "library"), response.parsed_body["url"]
    refute LibraryFolder.exists?(child.id)
    redo_receipt = response.parsed_body["receipt"]
    patch redo_library_edit_controls_url(@library), params: { receipt: redo_receipt, context: { folder_id: @root.id } }, headers: @headers, as: :json
    assert_response :success
    assert LibraryFolder.exists?(child.id)
  end

  test "multi-item receipts undo and redo all items atomically" do
    changes = place([ contents(:one).id, contents(:two).id ])
    receipt = issue(changes)
    initial_receipt = receipt
    get status_library_edit_controls_url(@library), params: { receipt:, direction: "undo" }, headers: @headers
    assert_response :success
    assert_equal "Add content (2 items)", response.parsed_body["label"]
    patch undo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers, as: :json
    assert_response :success
    assert_empty @root.library_folder_contents
    receipt = response.parsed_body["receipt"]
    patch redo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers, as: :json
    assert_response :success
    assert_equal 2, @root.library_folder_contents.count
    new_receipt = response.parsed_body["receipt"]
    refute_equal initial_receipt, new_receipt
    assert_equal changes.map(&:id), LibraryChanges::PageReceipt.resolve(receipt: new_receipt,
      user: @user, library: @library, page_session: @page_session).map(&:id)
    patch undo_library_edit_controls_url(@library), params: { receipt: initial_receipt }, headers: @headers, as: :json
    assert_response :conflict
    assert_equal 2, @root.library_folder_contents.count
    patch redo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers, as: :json
    assert_response :conflict
    patch undo_library_edit_controls_url(@library), params: { receipt: new_receipt }, headers: @headers, as: :json
    assert_response :success
    assert_empty @root.library_folder_contents
  end

  test "foreign dependencies block the entire batch without changing unaffected members" do
    changes = place([ contents(:one).id, contents(:two).id ])
    other = users(:two)
    other.update!(role: :admin)
    LibraryFolderOperations::Remove.call(library: @library, source_folder_id: @root.id,
      folder_ids: [], content_ids: [ contents(:two).id ], user: other)
    patch undo_library_edit_controls_url(@library), params: { receipt: issue(changes) }, headers: @headers, as: :json
    assert_response :conflict
    assert_includes response.parsed_body["reason"], "dependent edits"
    assert @root.library_folder_contents.exists?(content: contents(:one))
    assert changes.all? { |change| !change.reload.undone? }
  end

  test "receipts cannot be forged reused by another page or used for another user or library" do
    changes = place([ contents(:one).id ])
    receipt = issue(changes)
    [ receipt + "bad", "invalid" ].each do |invalid|
      patch undo_library_edit_controls_url(@library), params: { receipt: invalid }, headers: @headers, as: :json
      assert_response :conflict
    end
    patch undo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers.merge(LibraryChanges::PageReceipt::SESSION_HEADER => SecureRandom.uuid), as: :json
    assert_response :conflict
    other_library = Library.create!(name: "Other", user: @user)
    patch undo_library_edit_controls_url(other_library), params: { receipt: }, headers: @headers, as: :json
    assert_response :conflict
    other = users(:two)
    other.update!(role: :admin)
    sign_in other
    patch undo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers, as: :json
    assert_response :conflict
    assert @root.library_folder_contents.exists?(content: contents(:one))
  end

  test "only editors receive controls and can use endpoints while history remains admin only" do
    changes = place([ contents(:one).id ])
    receipt = issue(changes)
    get library_url(@library)
    assert_select "[data-controller='library-undo']"
    get library_changes_url(@library)
    assert_redirected_to root_url
    @user.update!(role: :intern)
    get library_url(@library)
    assert_select "[data-controller='library-undo']", count: 0
    patch undo_library_edit_controls_url(@library), params: { receipt: }, headers: @headers, as: :json
    assert_response :forbidden
  end

  test "version changes invalidate receipts and previous versions have no controls" do
    receipt = issue(place([ contents(:one).id ]))
    previous = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)
    get status_library_edit_controls_url(@library), params: { receipt: }, headers: @headers
    assert_response :conflict
    get library_url(@library, library_version_id: previous.id)
    assert_select "[data-controller='library-undo']", count: 0
  end

  test "failed submissions and no-op placements do not issue receipts" do
    post library_library_folders_url(@library), params: { library_folder: { name: "" }, parent_folder_id: @root.id },
      headers: @headers.merge("Accept" => "text/vnd.turbo-stream.html")
    assert_response :unprocessable_content
    assert_nil response.headers[LibraryChanges::PageReceipt::HEADER]
    result = LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: @root.id, content_ids: [ contents(:one).id ], user: @user)
    repeated = LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: @root.id, content_ids: [ contents(:one).id ], user: @user)
    assert_equal 1, result.recorded_changes.length
    assert_empty repeated.recorded_changes
    assert_nil issue(repeated.recorded_changes)
  end

  private

  def place(ids)
    LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: @root.id, content_ids: ids, user: @user).recorded_changes
  end

  def issue(changes)
    LibraryChanges::PageReceipt.issue(changes:, user: @user, page_session: @page_session)
  end
end
