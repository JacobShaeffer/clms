require "test_helper"

class LibraryAssetsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    users(:one).update!(role: :intern_plus)
    sign_in users(:one)
    @library_asset = library_assets(:one)
    attach_library_asset_files(@library_asset)
  end

  test "should get index" do
    get library_assets_url
    assert_response :success
    assert_select "#library_assets.row.row-cols-1.row-cols-sm-2.row-cols-lg-3.row-cols-xl-4"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@library_asset, :listing)}.col .card.h-100" do
      assert_select ".card-img-top.ratio.ratio-4x3 img[alt='#{@library_asset.name} image']", count: 1
      assert_select ".card-body"
      assert_select "a[href*='/rails/active_storage/blobs/']", text: "Download design files", count: 1
    end
    assert_select "a[href='#{library_asset_path(@library_asset)}'][data-turbo-frame='modal']", text: "Show"
    assert_select "a[href='#{edit_library_asset_path(@library_asset)}'][data-turbo-frame='modal']", text: "Edit"
    assert_select "a[href='#{delete_confirmation_library_asset_path(@library_asset)}'][data-turbo-frame='modal']", text: "Destroy"
    assert_select "#library-navigation button.dropdown-toggle[data-bs-toggle='dropdown']", count: 1
    assert_select "#library-navigation a.dropdown-item[href='#{library_assets_path}']", text: "Library Assets", count: 1
    assert_select "form[data-turbo-frame='library_asset_results'] input[type='search'][name='q']"
    assert_select "fieldset[aria-label='Language'] button[aria-pressed='true']", text: "All", count: 1
    assert_select "fieldset[aria-label='Type'] button[aria-pressed='true']", text: "All", count: 1
    assert_select "fieldset[aria-label='Language'] button", count: 5
    assert_select "fieldset[aria-label='Type'] button", count: 4
  end

  test "searches asset names without regard to case and treats wildcards literally" do
    matching = create_filter_asset!(name: "Travel Guide 100%_", language: "English", asset_type: "Banner")
    create_filter_asset!(name: "Travel Guide 100AA", language: "English", asset_type: "Banner")

    get library_assets_url, params: { q: " guide 100%_ " }

    assert_response :success
    assert_select "#library_assets > .col", count: 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(matching, :listing)}"
    assert_select "input[name='q'][value='guide 100%_']"
  end

  test "combines name language and type filters in the results frame" do
    matching = create_filter_asset!(name: "English Module Guide", language: "English", asset_type: "Module")
    create_filter_asset!(name: "English Banner Guide", language: "English", asset_type: "Banner")
    create_filter_asset!(name: "French Module Guide", language: "French", asset_type: "Module")
    create_filter_asset!(name: "English Module Poster", language: "English", asset_type: "Module")

    get library_assets_url,
      params: { q: "guide", language: "English", asset_type: "Module" },
      headers: { "Turbo-Frame" => "library_asset_results" }

    assert_response :success
    assert_select "turbo-frame#library_asset_results #library_assets > .col", count: 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(matching, :listing)}"
    assert_select "fieldset[aria-label='Language'] button[aria-pressed='true']", text: "English", count: 1
    assert_select "fieldset[aria-label='Type'] button[aria-pressed='true']", text: "Module", count: 1
    assert_select "a[href='#{edit_library_asset_path(matching, library_asset_filters: { q: "guide", language: "English", asset_type: "Module" })}']"
  end

  test "invalid filters fall back to all assets without failing" do
    get library_assets_url, params: { q: [ "guide" ], language: [ "English" ], asset_type: "Unknown" }

    assert_response :success
    assert_select "#library_assets > .col", count: LibraryAsset.count
    assert_select "fieldset[aria-label='Language'] button[aria-pressed='true']", text: "All"
    assert_select "fieldset[aria-label='Type'] button[aria-pressed='true']", text: "All"
  end

  test "empty results retain controls and explain that no assets match" do
    get library_assets_url, params: { q: "unmatched asset" }

    assert_response :success
    assert_select "#library_assets > .col", count: 0
    assert_select "turbo-frame#library_asset_results [role='status']", text: "No library assets match your search and filters."
    assert_select "fieldset[aria-label='Language'] button", count: 5
  end

  test "creating an asset respects the active filters" do
    assert_difference("LibraryAsset.count") do
      post library_assets_url,
        params: {
          library_asset: {
            name: "French Module", language: "French", asset_type: "Module",
            image: fixture_file_upload("library_asset.png", "image/png")
          },
          library_asset_filters: { language: "English", asset_type: "Module" }
        },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    assert_select "turbo-stream[action='update'][target='library_asset_results']" do
      assert_select "#library_assets > .col", count: 0
      assert_select "[role='status']"
    end
  end

  test "editing an asset out of the selected language removes it from results" do
    matching = create_filter_asset!(name: "English Module Guide", language: "English", asset_type: "Module")

    patch library_asset_url(matching),
      params: {
        library_asset: { language: "French" },
        library_asset_filters: { q: "guide", language: "English", asset_type: "Module" }
      },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal "French", matching.reload.language
    assert_select "turbo-stream[action='update'][target='library_asset_results']" do
      assert_select "#library_assets > .col", count: 0
    end
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(matching)}']"
  end

  test "modal forms preserve search and filter state" do
    filters = { q: "guide", language: "English", asset_type: "Module" }
    [ new_library_asset_url, edit_library_asset_url(@library_asset), delete_confirmation_library_asset_url(@library_asset) ].each do |url|
      get url, params: { library_asset_filters: filters }, headers: TURBO_FRAME_HEADERS

      assert_response :success
      filters.each do |field, value|
        assert_select "input[name='library_asset_filters[#{field}]'][value='#{value}']"
      end
    end
  end

  test "user below intern plus cannot access library assets or see the library dropdown" do
    sign_out users(:one)
    users(:two).update!(role: :intern)
    sign_in users(:two)

    get library_assets_url

    assert_redirected_to root_url

    follow_redirect!
    assert_select "#library-navigation button.dropdown-toggle[data-bs-toggle='dropdown']", count: 0
    assert_select "#library-navigation a.dropdown-item[href='#{library_assets_path}']", count: 0
  end

  test "should get new" do
    get new_library_asset_url
    assert_response :success
    assert_select "input[type='file'][name='library_asset[image]'][accept='image/png,.png']"
    assert_select "input[type='file'][name='library_asset[design_files]'][accept='application/zip,.zip']"
    assert_select "form [required]", count: 1
    assert_select "input#library_asset_image[required]"
    assert_select "input#library_asset_language[list='library-asset-languages']"
    assert_select "datalist#library-asset-languages option" do |options|
      assert_equal %w[ English French Spanish Arabic ], options.map { |option| option["value"] }
    end
    assert_select "label[for='library_asset_asset_type']", text: "Type"
    assert_select "select.form-select#library_asset_asset_type:not([required]) option" do |options|
      assert_equal [ "", "Banner", "Subject", "Module" ], options.map { |option| option["value"] }
    end
  end

  test "should get new in modal" do
    get new_library_asset_url, headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select "form[data-turbo-frame='modal']"
  end

  test "should create library_asset" do
    assert_difference("LibraryAsset.count") do
      post library_assets_url, params: {
        library_asset: {
          language: @library_asset.language,
          name: "New Library Asset",
          asset_type: "Module",
          image: fixture_file_upload("library_asset.png", "image/png"),
          design_files: fixture_file_upload("design_files.zip", "application/zip")
        }
      }
    end

    created_library_asset = LibraryAsset.last
    assert_equal users(:one), created_library_asset.user
    assert created_library_asset.image.attached?
    assert created_library_asset.design_files.attached?
    assert_equal "Module", created_library_asset.asset_type
    assert_redirected_to library_asset_url(created_library_asset)
  end

  test "creates an asset with only an image" do
    assert_difference("LibraryAsset.count") do
      post library_assets_url, params: {
        library_asset: { image: fixture_file_upload("library_asset.png", "image/png") }
      }
    end

    asset = LibraryAsset.last
    assert_redirected_to library_asset_url(asset)
    assert asset.image.attached?
    assert_nil asset.name
    assert_nil asset.language
    assert_nil asset.asset_type
    refute asset.design_files.attached?

    get library_asset_url(asset)
    assert_select "h2.card-title", text: "library_asset.png"
  end

  test "should render create errors in modal" do
    assert_no_difference("LibraryAsset.count") do
      post library_assets_url,
        params: { library_asset: { language: "English", name: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']"
    end
  end

  test "should show library_asset" do
    get library_asset_url(@library_asset)
    assert_response :success
  end

  test "should show library_asset in modal" do
    get library_asset_url(@library_asset), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select ".modal-title", text: "Library asset"
  end

  test "should get edit" do
    get edit_library_asset_url(@library_asset)
    assert_response :success
  end

  test "should get edit in modal" do
    get edit_library_asset_url(@library_asset), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select "form[data-turbo-frame='modal']"
    assert_select "form [required]", count: 0
  end

  test "should update library_asset" do
    patch library_asset_url(@library_asset), params: { library_asset: { language: "French", name: "", asset_type: "Banner" } }
    assert_redirected_to library_asset_url(@library_asset)
    assert_equal "", @library_asset.reload.name
    assert_equal "French", @library_asset.language
    assert_equal "Banner", @library_asset.asset_type
    assert @library_asset.image.attached?
  end

  test "should render update errors in modal" do
    patch library_asset_url(@library_asset),
      params: { library_asset: { language: @library_asset.language, asset_type: "Unsupported" } },
      headers: TURBO_STREAM_HEADERS

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger[role='alert']"
    end
  end

  test "should show delete confirmation in modal" do
    get delete_confirmation_library_asset_url(@library_asset), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal[data-controller='modal']"
    assert_select ".modal-title", text: "Delete library asset"
    assert_select "form[data-turbo-frame='modal'][action='#{library_asset_path(@library_asset)}']"
  end

  test "should destroy library_asset from modal" do
    assert_difference("LibraryAsset.count", -1) do
      delete library_asset_url(@library_asset), headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='update'][target='library_asset_results']" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@library_asset, :listing)}", count: 0
    end
  end

  test "should destroy library_asset" do
    assert_difference("LibraryAsset.count", -1) do
      delete library_asset_url(@library_asset)
    end

    assert_redirected_to library_assets_url
  end

  private

  def create_filter_asset!(name:, language:, asset_type:)
    LibraryAsset.new(user: users(:one), name:, language:, asset_type:).tap do |asset|
      attach_library_asset_files(asset)
      asset.save!
    end
  end

  def attach_library_asset_files(library_asset)
    library_asset.image.attach(
      io: StringIO.new("PNG contents"),
      filename: "preview.png",
      content_type: "image/png"
    )
    library_asset.design_files.attach(
      io: StringIO.new("ZIP contents"),
      filename: "design_files.zip",
      content_type: "application/zip"
    )
  end
end
