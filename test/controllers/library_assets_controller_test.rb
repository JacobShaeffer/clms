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
    assert_select "button.dropdown-toggle[data-bs-toggle='dropdown']", count: 1
    assert_select "a.dropdown-item[href='#{library_assets_path}']", text: "Library Assets", count: 1
  end

  test "user below intern plus cannot access library assets or see the library dropdown" do
    sign_out users(:one)
    users(:two).update!(role: :intern)
    sign_in users(:two)

    get library_assets_url

    assert_redirected_to root_url

    follow_redirect!
    assert_select "button.dropdown-toggle[data-bs-toggle='dropdown']", count: 0
    assert_select "a.dropdown-item[href='#{library_assets_path}']", count: 0
  end

  test "should get new" do
    get new_library_asset_url
    assert_response :success
    assert_select "input[type='file'][name='library_asset[image]'][accept='image/png,.png']"
    assert_select "input[type='file'][name='library_asset[design_files]'][accept='application/zip,.zip']"
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
          image: fixture_file_upload("library_asset.png", "image/png"),
          design_files: fixture_file_upload("design_files.zip", "application/zip")
        }
      }
    end

    created_library_asset = LibraryAsset.last
    assert_equal users(:one), created_library_asset.user
    assert created_library_asset.image.attached?
    assert created_library_asset.design_files.attached?
    assert_redirected_to library_asset_url(created_library_asset)
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
  end

  test "should update library_asset" do
    patch library_asset_url(@library_asset), params: { library_asset: { language: @library_asset.language, name: @library_asset.name } }
    assert_redirected_to library_asset_url(@library_asset)
  end

  test "should render update errors in modal" do
    patch library_asset_url(@library_asset),
      params: { library_asset: { language: @library_asset.language, name: "" } },
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
    listing_id = ActionView::RecordIdentifier.dom_id(@library_asset, :listing)

    assert_difference("LibraryAsset.count", -1) do
      delete library_asset_url(@library_asset), headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='remove'][target='#{listing_id}']"
  end

  test "should destroy library_asset" do
    assert_difference("LibraryAsset.count", -1) do
      delete library_asset_url(@library_asset)
    end

    assert_redirected_to library_assets_url
  end

  private

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
