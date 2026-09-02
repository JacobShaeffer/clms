require "test_helper"

class LibraryFolderSelectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    @user = users(:one)
    @user.update!(
      name: "Folder Manager",
      email: "folder-manager@example.com",
      password: "password",
      role: :intern_plus
    )
    sign_in @user

    @library = Library.create!(name: "Health Library", user: @user)
    @source = create_folder!("Source")
    @selected_folder = create_folder!("Selected", parent_folder: @source)
    @nested = create_folder!("Nested", parent_folder: @selected_folder)
    @destination = create_folder!("Destination")
    LibraryFolderContent.create!(library_folder: @source, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @nested, content: contents(:two))
  end

  test "remove confirmation lists direct and recursive items in a nested tree" do
    get remove_confirmation_library_folder_selection_url(@library),
      params: selection_params,
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Remove selected items"
    assert_select ".modal-dialog.modal-lg.modal-dialog-scrollable"
    assert_select "ul" do
      assert_select "li", text: /#{Regexp.escape(contents(:one).title)}/
      assert_select "li", text: /#{@selected_folder.name}/ do
        assert_select "li", text: /#{@nested.name}/ do
          assert_select "li", text: /#{Regexp.escape(contents(:two).title)}/
        end
      end
    end
    assert_select "form[action='#{remove_library_folder_selection_path(@library)}']" do
      assert_select "input[name='folder_ids[]'][value='#{@selected_folder.id}']"
      assert_select "input[name='content_ids[]'][value='#{contents(:one).id}']"
      assert_select "button.btn-danger", text: "Remove"
    end
  end

  test "move picker shows only folders and disables invalid destinations" do
    get move_library_folder_selection_url(@library),
      params: selection_params,
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Move items"
    assert_select "turbo-frame#library-folder-destination-browser" do
      assert_select "a[data-turbo-frame='library-folder-destination-browser']", text: @source.name
      assert_select "input[name='destination_folder_id']", count: 0
    end
    assert_select "button", text: "Move Here", disabled: true
    assert_select "#library-folder-destination-items", text: /#{Regexp.escape(contents(:one).title)}/, count: 0

    get move_library_folder_selection_url(@library),
      params: selection_params.merge(picker_folder_id: @source.id),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "input[type='hidden'][name='destination_folder_id'][value='#{@source.id}'][disabled]"
    assert_select "#library-folder-destination-items a", text: @selected_folder.name, count: 0
    assert_select "#library-folder-destination-items", text: /#{@selected_folder.name}/
    assert_select "button", text: "Move Here", disabled: true

    get move_library_folder_selection_url(@library),
      params: selection_params.merge(picker_folder_id: @destination.id),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "input[type='hidden'][name='destination_folder_id']" \
      "[value='#{@destination.id}']:not([disabled])"
    assert_select "button", text: "Move Here", disabled: false
  end

  test "duplicate picker uses duplicate labels and allows the source parent" do
    get duplicate_library_folder_selection_url(@library),
      params: selection_params,
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Duplicate items"
    assert_select "input[name='destination_folder_id']", count: 0
    assert_select "button", text: "Duplicate Here", disabled: true
    assert_select "a.btn.btn-success[data-turbo-frame='modal']", text: "New Folder"

    get duplicate_library_folder_selection_url(@library),
      params: selection_params.merge(
        picker_folder_id: @source.id
      ),
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "input[type='hidden'][name='destination_folder_id']" \
      "[value='#{@source.id}']:not([disabled])"
    assert_select "button", text: "Duplicate Here", disabled: false
  end

  test "move transfers selected folders and content and refreshes the page" do
    patch apply_move_library_folder_selection_url(@library),
      params: selection_params.merge(destination_folder_id: @destination.id),
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal @destination, @selected_folder.reload.parent_folder
    assert @destination.contents.exists?(contents(:one).id)
    refute @source.contents.exists?(contents(:one).id)
    assert_select "turbo-stream[action='refresh']"
  end

  test "duplicate copies selected folders and content and refreshes the page" do
    assert_difference("LibraryFolder.count", 2) do
      post apply_duplicate_library_folder_selection_url(@library),
        params: selection_params.merge(destination_folder_id: @destination.id),
        headers: TURBO_STREAM_HEADERS
    end

    copied_folder = @destination.child_folders.find_by!(name: @selected_folder.name)
    assert copied_folder.child_folders.exists?(name: @nested.name)
    assert @destination.contents.exists?(contents(:one).id)
    assert_equal @source, @selected_folder.reload.parent_folder
    assert_select "turbo-stream[action='refresh']"
  end

  test "remove deletes the selected tree and placement and refreshes the page" do
    assert_no_difference("Content.count") do
      delete remove_library_folder_selection_url(@library),
        params: selection_params,
        headers: TURBO_STREAM_HEADERS
    end

    refute LibraryFolder.exists?(@selected_folder.id)
    refute LibraryFolder.exists?(@nested.id)
    refute @source.contents.exists?(contents(:one).id)
    assert_select "turbo-stream[action='refresh']"
  end

  test "invalid and stale selections return a modal error" do
    get move_library_folder_selection_url(@library),
      params: selection_params.merge(folder_ids: [ 999_999 ]),
      headers: TURBO_FRAME_HEADERS

    assert_response :unprocessable_content
    assert_select "turbo-frame#modal .modal-title", text: "Folder operation unavailable"
    assert_select ".alert-danger", text: /no longer available/
  end

  test "foreign destinations return not found without changing data" do
    other_library = Library.create!(name: "Other", user: @user)
    foreign_destination = create_folder!("Foreign", library: other_library)

    assert_no_changes -> { @selected_folder.reload.parent_folder_id } do
      patch apply_move_library_folder_selection_url(@library),
        params: selection_params.merge(destination_folder_id: foreign_destination.id),
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :not_found
  end

  test "users below intern plus cannot manage folder selections" do
    @user.update!(role: :intern)

    get move_library_folder_selection_url(@library),
      params: selection_params,
      headers: TURBO_FRAME_HEADERS

    assert_redirected_to root_url
  end

  private

  def selection_params
    {
      source_folder_id: @source.id,
      folder_ids: [ @selected_folder.id ],
      content_ids: [ contents(:one).id ],
      tab: "all"
    }
  end

  def create_folder!(name, library: @library, parent_folder: nil)
    library.library_folders.create!(
      name:,
      parent_folder:,
      user: @user,
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end
end
