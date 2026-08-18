require "test_helper"

class ShelvesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_STREAM_HEADERS = {
    "Turbo-Frame" => "modal",
    "Accept" => "text/vnd.turbo-stream.html"
  }.freeze

  setup do
    @user = users(:one)
    @user.update!(role: :organization)
    @user.active_shelves.delete_all
    @user.content_table_preferences.delete_all
    @shelf = shelves(:one)
    @shelf.update!(name: "History")
    sign_in @user
  end

  test "index renders five active slots and only the current user's archived shelves" do
    second_shelf = @user.shelves.create!(name: "Audio")
    ActiveShelf.activate!(user: @user, shelf: @shelf)

    get shelves_url

    assert_response :success
    assert_select "h1", text: "Shelves"
    assert_select "#active-shelves li", count: 5
    assert_select "#active-shelves [data-active-shelf-empty-slot]", count: 4
    assert_select "#active-shelves a", text: @shelf.name
    assert_select "#archived-shelves a", text: second_shelf.name
    assert_select "#archived-shelves", text: shelves(:two).name, count: 0
    assert_select "a.btn.btn-success[data-turbo-frame='modal'][aria-label='Create shelf']", text: "+"
    assert_select "turbo-frame#modal"
  end

  test "new renders the shelf form in a modal" do
    get new_shelf_url(selected_shelf_id: @shelf.id), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "New shelf"
    assert_select "form[action='#{shelves_path}'][data-turbo-frame='modal']" do
      assert_select "input[name='selected_shelf_id'][value='#{@shelf.id}']"
      assert_select "input#shelf_name[name='shelf[name]']"
      assert_select "input.btn.btn-success[type='submit'][value='Create Shelf']"
    end
  end

  test "create prepends an active shelf and preserves the selected shelf" do
    ActiveShelf.activate!(user: @user, shelf: @shelf)

    assert_difference([ "Shelf.count", "ActiveShelf.count" ], 1) do
      post shelves_url,
        params: { shelf: { name: "New shelf" }, selected_shelf_id: @shelf.id },
        headers: TURBO_STREAM_HEADERS
    end

    created = @user.shelves.find_by!(name: "New shelf")
    assert_equal [ created.id, @shelf.id ], @user.active_shelves.ordered.pluck(:shelf_id)
    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='shelf-lists']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@shelf, :active)}[aria-current='true']"
  end

  test "create archives the previous fifth active shelf" do
    existing_shelves = [ @shelf ] + 4.times.map { |index| @user.shelves.create!(name: "Existing #{index}") }
    existing_shelves.each { |shelf| ActiveShelf.activate!(user: @user, shelf:) }

    assert_difference("Shelf.count", 1) do
      assert_no_difference("ActiveShelf.count") do
        post shelves_url,
          params: { shelf: { name: "New shelf" } },
          headers: TURBO_STREAM_HEADERS
      end
    end

    created = @user.shelves.find_by!(name: "New shelf")
    assert_equal [ created.id ] + existing_shelves.first(4).map(&:id),
      @user.active_shelves.ordered.pluck(:shelf_id)
    refute @user.active_shelves.exists?(shelf: existing_shelves.last)
    assert_select "##{ActionView::RecordIdentifier.dom_id(existing_shelves.last, :archived)}"
  end

  test "invalid create rerenders the modal without creating a shelf" do
    assert_no_difference([ "Shelf.count", "ActiveShelf.count" ]) do
      post shelves_url,
        params: { shelf: { name: " " } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger",
      text: /Name can't be blank/
  end

  test "selecting either list uses one shared selection" do
    archived_shelf = @user.shelves.create!(name: "Archived")
    ActiveShelf.activate!(user: @user, shelf: @shelf)

    get shelves_url(selected_shelf_id: archived_shelf.id)

    assert_response :success
    assert_select "#active-shelves li[aria-current]", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(archived_shelf, :archived)}[aria-current='true']", count: 1
    assert_select "#selected-shelf-heading + p", text: archived_shelf.name

    get shelves_url(selected_shelf_id: @shelf.id)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@shelf, :active)}[aria-current='true']", count: 1
    assert_select "#archived-shelves li[aria-current]", count: 0
  end

  test "an archived shelf can be made active" do
    assert_difference("ActiveShelf.count", 1) do
      patch activate_shelf_url(@shelf)
    end

    assert_redirected_to shelves_url(selected_shelf_id: @shelf.id)
    assert_equal [ @shelf ], @user.active_shelves.ordered.map(&:shelf)
  end

  test "only five shelves can be active" do
    shelves = [ @shelf ] + 5.times.map { |index| @user.shelves.create!(name: "Shelf #{index}") }
    shelves.first(5).each { |shelf| ActiveShelf.activate!(user: @user, shelf:) }

    assert_no_difference("ActiveShelf.count") do
      patch activate_shelf_url(shelves.last)
    end

    assert_redirected_to shelves_url(selected_shelf_id: shelves.last.id)
    follow_redirect!
    assert_select ".alert", text: /Only five shelves can be active/
  end

  test "an active shelf can be archived and positions close up" do
    second_shelf = @user.shelves.create!(name: "Second")
    ActiveShelf.activate!(user: @user, shelf: @shelf)
    ActiveShelf.activate!(user: @user, shelf: second_shelf)

    assert_difference("ActiveShelf.count", -1) do
      patch archive_shelf_url(@shelf)
    end

    assert_redirected_to shelves_url(selected_shelf_id: @shelf.id)
    assert_equal [ [ second_shelf.id, 1 ] ], @user.active_shelves.ordered.pluck(:shelf_id, :position)
  end

  test "active shelves can be reordered and the order is stored" do
    second_shelf = @user.shelves.create!(name: "Second")
    ActiveShelf.activate!(user: @user, shelf: @shelf)
    ActiveShelf.activate!(user: @user, shelf: second_shelf)

    patch move_shelf_url(second_shelf, direction: :up)

    assert_redirected_to shelves_url(selected_shelf_id: second_shelf.id)
    assert_equal [ second_shelf.id, @shelf.id ], @user.active_shelves.ordered.pluck(:shelf_id)
    assert_equal [ 1, 2 ], @user.active_shelves.ordered.pluck(:position)
  end

  test "selected shelf renders only its content and shows its shelves column by default" do
    second_shelf = @user.shelves.create!(name: "Reference")
    second_shelf.contents << contents(:one)
    contents(:one).update_column(:title, "History Document")
    contents(:two).update_column(:title, "Unrelated Document")

    get shelves_url(selected_shelf_id: @shelf.id)

    assert_response :success
    assert_select "turbo-frame#shelf_#{@shelf.id}_contents_table"
    assert_select "turbo-frame#shelf_#{@shelf.id}_contents_table thead input[data-content-table-selection-target='page']"
    assert_select "turbo-frame#shelf_#{@shelf.id}_contents_table tbody input[data-content-table-selection-target='row']"
    assert_select "th", text: "Shelves"
    assert_select "tbody td", text: "History Document"
    assert_select "tbody td", text: "History, Reference"
    assert_select "tbody td", text: "Unrelated Document", count: 0
  end

  test "selected shelf search is case insensitive and persists independently per shelf" do
    second_shelf = @user.shelves.create!(name: "Second")
    second_shelf.contents << contents(:one)
    contents(:one).update_column(:title, "Mixed CASE Title")

    get table_shelf_url(@shelf, q: "mixed case")

    assert_response :success
    assert_select "tbody td", text: "Mixed CASE Title"
    first_preference = @user.content_table_preferences.find_by!(table_key: "shelves.#{@shelf.id}.contents")
    assert_equal "mixed case", first_preference.state.fetch("q")

    get shelves_url(selected_shelf_id: second_shelf.id)

    assert_response :success
    assert_select "input[type='search'][value='']"

    get shelves_url(selected_shelf_id: @shelf.id)

    assert_response :success
    assert_select "input[type='search'][value='mixed case']"
  end

  test "reset deletes only the selected shelf table preference" do
    other_shelf = @user.shelves.create!(name: "Other")
    first = @user.content_table_preferences.create!(table_key: "shelves.#{@shelf.id}.contents", state: { "q" => "one" })
    second = @user.content_table_preferences.create!(table_key: "shelves.#{other_shelf.id}.contents", state: { "q" => "two" })

    delete reset_table_shelf_url(@shelf)

    assert_redirected_to shelves_url(selected_shelf_id: @shelf.id)
    refute ContentTablePreference.exists?(first.id)
    assert ContentTablePreference.exists?(second.id)
  end

  test "another user's shelf cannot be selected or changed" do
    get shelves_url(selected_shelf_id: shelves(:two).id)
    assert_response :not_found

    sign_in @user
    patch activate_shelf_url(shelves(:two))
    assert_response :not_found
  end

  test "index renders an empty state" do
    @user.shelves.destroy_all

    get shelves_url

    assert_response :success
    assert_select "#active-shelves [data-active-shelf-empty-slot]", count: 5
    assert_select "#archived-shelves", text: "No archived shelves."
    assert_select "#selected-shelf-heading + p", text: "Select a shelf to view its content."
  end

  test "guest cannot access shelves or see the content dropdown" do
    sign_out @user
    sign_in users(:two)

    get shelves_url

    assert_redirected_to root_url
    follow_redirect!
    assert_select "#content-navigation a[href='#{contents_path}']", text: "Content", count: 1
    assert_select "#content-navigation button.dropdown-toggle", count: 0
    assert_select "#content-navigation a[href='#{shelves_path}']", count: 0
  end

  test "anonymous user must sign in" do
    sign_out @user

    get shelves_url

    assert_redirected_to new_user_session_url
  end
end
