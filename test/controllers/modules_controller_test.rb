require "test_helper"

class ModulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    users(:one).update!(role: :intern_plus)
    sign_in users(:one)
    @library_module = LibraryModule.create!(
      user: users(:one),
      name: "Health Basics",
      folder_name: "health-basics",
      icon: library_assets(:one)
    )
  end

  test "index renders modules search table navigation and accessible actions" do
    get modules_url

    assert_response :success
    assert_select "title", text: "Modules"
    assert_select "h1", text: "Modules"
    assert_select "a.btn.btn-primary[data-turbo-frame='modal']", text: "New Module"
    assert_select "form[data-turbo-frame='module_results'] input[type='search'][name='q']"
    assert_select "thead th", text: "Name"
    assert_select "thead th", text: "Folder Name"
    assert_select "thead th", text: "Library asset"
    assert_select "thead .visually-hidden", text: "Actions"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@library_module)}" do
      assert_select "td", text: @library_module.name
      assert_select "td", text: @library_module.folder_name
      assert_select "td", text: @library_module.icon.display_name
      assert_select "a[aria-label='Show #{@library_module.name}'][title='Show'] i.bi.bi-eye[aria-hidden='true']"
      assert_select "a[aria-label='Edit #{@library_module.name}'][title='Edit'] i.bi.bi-pencil-square[aria-hidden='true']"
      assert_select "a[aria-label='Destroy #{@library_module.name}']", count: 0
    end
    assert_select "#library-navigation a.dropdown-item[href='#{modules_path}']", text: "Modules"
  end

  test "searches names without regard to case and treats wildcards literally" do
    matching = create_module!(name: "Travel Guide 100%_", folder_name: "travel")
    create_module!(name: "Travel Guide 100AA", folder_name: "other")

    get modules_url, params: { q: " guide 100%_ " }

    assert_response :success
    assert_select "#modules tr", count: 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(matching)}"
    assert_select "input[name='q'][value='guide 100%_']"
  end

  test "invalid query values fall back to all modules" do
    get modules_url, params: { q: [ "Health" ] }

    assert_response :success
    assert_select "#modules tr", count: LibraryModule.count
  end

  test "index renders an empty state" do
    get modules_url, params: { q: "not found" }

    assert_response :success
    assert_select "#modules td[colspan='4']", text: "No modules match your search."
  end

  test "new modal requires all fields and offers every library asset" do
    get new_module_url, headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select "form[action='#{modules_path}'][data-turbo-frame='modal']"
    assert_select "input[name='library_module[name]'][required]"
    assert_select "input[name='library_module[folder_name]'][required]"
    assert_select "select[name='library_module[icon_id]'][required] option", count: LibraryAsset.count + 1
  end

  test "creates a module from the modal and refreshes filtered results" do
    assert_difference("LibraryModule.count") do
      post modules_url,
        params: {
          library_module: {
            name: "Nutrition",
            folder_name: "nutrition",
            icon_id: library_assets(:two).id
          },
          module_filters: { q: "nutrition" }
        },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    created = LibraryModule.order(:id).last
    assert_equal users(:one), created.user
    assert_equal library_assets(:two), created.icon
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='update'][target='module_results']" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(created)}"
      assert_select "##{ActionView::RecordIdentifier.dom_id(@library_module)}", count: 0
    end
  end

  test "allows duplicate module names" do
    assert_difference("LibraryModule.count") do
      post modules_url, params: {
        library_module: {
          name: @library_module.name,
          folder_name: "duplicate",
          icon_id: library_assets(:two).id
        }
      }
    end

    assert_response :redirect
  end

  test "invalid modal create renders errors" do
    assert_no_difference("LibraryModule.count") do
      post modules_url,
        params: { library_module: { name: "", folder_name: "", icon_id: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']"
    end
  end

  test "shows a module in the modal" do
    get module_url(@library_module),
      params: { module_filters: { q: "health" } },
      headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Module"
    assert_select "dd", text: @library_module.name
    assert_select "a[href='#{edit_module_path(@library_module, module_filters: { q: "health" })}']", text: "Edit"
  end

  test "updates a module from the modal and respects the active search" do
    patch module_url(@library_module),
      params: {
        library_module: { name: "First Aid" },
        module_filters: { q: "health" }
      },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal "First Aid", @library_module.reload.name
    assert_select "turbo-stream[action='update'][target='module_results']" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@library_module)}", count: 0
      assert_select "td[colspan='4']", text: "No modules match your search."
    end
  end

  test "invalid modal update renders errors" do
    patch module_url(@library_module),
      params: { library_module: { name: "" } },
      headers: TURBO_STREAM_HEADERS

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']"
    end
  end

  test "intern plus cannot open delete confirmation or destroy a module" do
    get delete_confirmation_module_url(@library_module), headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    assert_no_difference("LibraryModule.count") do
      delete module_url(@library_module), headers: TURBO_STREAM_HEADERS
    end
    assert_redirected_to root_url
  end

  test "admin sees the destroy action and can destroy a module from the modal" do
    users(:one).update!(role: :admin)

    get modules_url
    assert_select "a[aria-label='Destroy #{@library_module.name}'][title='Destroy'] i.bi.bi-trash[aria-hidden='true']"

    get delete_confirmation_module_url(@library_module), headers: TURBO_FRAME_HEADERS
    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Delete Module"
    assert_select "form[action='#{module_path(@library_module)}'][data-turbo-frame='modal']"

    assert_difference("LibraryModule.count", -1) do
      delete module_url(@library_module), headers: TURBO_STREAM_HEADERS
    end
    assert_response :success
    assert_select "turbo-stream[action='update'][target='module_results']" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@library_module)}", count: 0
    end
  end

  test "users below intern plus cannot access modules or see the navigation item" do
    sign_out users(:one)
    users(:two).update!(role: :intern)
    sign_in users(:two)

    get modules_url

    assert_redirected_to root_url
    follow_redirect!
    assert_select "#library-navigation a.dropdown-item[href='#{modules_path}']", count: 0
  end

  private

  def create_module!(name:, folder_name:)
    LibraryModule.create!(
      user: users(:one),
      name: name,
      folder_name: folder_name,
      icon: library_assets(:one)
    )
  end
end
