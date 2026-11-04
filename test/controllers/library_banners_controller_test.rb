require "test_helper"

class LibraryBannersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  setup do
    users(:one).update!(role: :intern_plus)
    sign_in users(:one)
    @library = Library.create!(name: "Health Library", user: users(:one))
    @banner = create_asset!(name: "Health Banner", asset_type: "Banner")
    @other_banner = create_asset!(name: "Nutrition Banner", asset_type: "Banner")
    @subject = create_asset!(name: "Health Subject", asset_type: "Subject")
  end

  test "edit modal offers only Banner assets" do
    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Choose Banner Image"
    assert_select "form[action='#{library_banner_path(@library)}'][data-turbo-frame='modal']"
    assert_select "input[type='search'][name='q']"
    assert_select "fieldset[aria-label='Language']"
    assert_select "fieldset[aria-label='Type']", count: 0
    assert_select "turbo-frame#image_selection_results" do
      assert_select "button[data-asset-id='#{@banner.id}'] img"
      assert_select "button[data-asset-id='#{@other_banner.id}'] img"
      assert_select "button[data-asset-id='#{@subject.id}']", count: 0
    end
  end

  test "edit disables submission when no Banner assets exist" do
    @banner.destroy!
    @other_banner.destroy!

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "[role='status']", text: "No library assets match your search and filters."
    assert_select "input[type='submit'][value='Choose'][disabled]"
    assert_select "select[name='library[banner_id]']", count: 0
  end

  test "updates the banner and replaces the banner region" do
    patch library_banner_url(@library),
      params: { library: { banner_id: @banner.id } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal @banner, @library.reload.banner
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(@library, :banner)}']" do
      assert_select "img[alt='#{@library.name} Banner']"
    end
  end

  test "previews the current banner and replaces it" do
    @library.update!(banner: @banner)

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS
    assert_select "[aria-label='Selected Image'] img[alt='#{@banner.display_name}']"
    assert_select "input[name='library[banner_id]'][value='#{@banner.id}']"
    assert_select "button[data-asset-id='#{@banner.id}'][aria-pressed='true']"

    patch library_banner_url(@library),
      params: { library: { banner_id: @other_banner.id } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal @other_banner, @library.reload.banner
  end

  test "search and language filter only banners even when another type is requested" do
    @banner.update!(language: "English")
    @other_banner.update!(language: "French")

    get edit_library_banner_url(@library),
      params: { q: " health ", language: "English", asset_type: "Subject" },
      headers: { "Turbo-Frame" => "image_selection_results" }

    assert_response :success
    assert_select "turbo-frame#image_selection_results button[data-asset-id]", count: 1
    assert_select "button[data-asset-id='#{@banner.id}']"
    assert_select ".modal", count: 0
  end

  test "rejects blank stale non Banner and non scalar selections" do
    invalid_ids = [ "", "invalid", LibraryAsset.maximum(:id) + 1, @subject.id, [ @banner.id ] ]

    invalid_ids.each do |banner_id|
      patch library_banner_url(@library),
        params: { library: { banner_id: banner_id } },
        headers: TURBO_STREAM_HEADERS

      assert_response :unprocessable_content
      assert_nil @library.reload.banner
      assert_select "turbo-stream[action='replace'][target='modal'] .alert-danger", text: /Banner is not available/
    end
  end

  test "lower roles cannot edit or update banners" do
    sign_out users(:one)
    users(:two).update!(role: :intern)
    sign_in users(:two)

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    patch library_banner_url(@library), params: { library: { banner_id: @banner.id } }
    assert_redirected_to root_url
    assert_nil @library.reload.banner
  end

  test "admin can edit banners" do
    users(:one).update!(role: :admin)

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
  end

  test "html update redirects to the library" do
    patch library_banner_url(@library), params: { library: { banner_id: @banner.id } }

    assert_redirected_to library_url(@library)
    assert_equal @banner, @library.reload.banner
  end

  private

  def create_asset!(name:, asset_type:)
    LibraryAsset.new(user: users(:one), name: name, asset_type: asset_type).tap do |asset|
      asset.image.attach(
        io: File.open(file_fixture("library_asset.png")),
        filename: "#{name.parameterize}.png",
        content_type: "image/png"
      )
      asset.save!
    end
  end
end
