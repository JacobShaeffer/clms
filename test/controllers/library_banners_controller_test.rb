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
    assert_select "turbo-frame#modal .modal-title", text: "Choose banner image"
    assert_select "form[action='#{library_banner_path(@library)}'][data-turbo-frame='modal']"
    assert_select "select[name='library[banner_id]'][required]" do
      assert_select "option[value='#{@banner.id}']", text: @banner.display_name
      assert_select "option[value='#{@other_banner.id}']", text: @other_banner.display_name
      assert_select "option[value='#{@subject.id}']", count: 0
    end
  end

  test "edit disables submission when no Banner assets exist" do
    @banner.destroy!
    @other_banner.destroy!

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "[role='status']", text: "No Banner library assets are available."
    assert_select "input[type='submit'][value='Save banner'][disabled]"
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
      assert_select "img[alt='#{@library.name} banner']"
    end
  end

  test "replaces an existing banner without offering a blank choice" do
    @library.update!(banner: @banner)

    get edit_library_banner_url(@library), headers: TURBO_FRAME_HEADERS
    assert_select "select[name='library[banner_id]'] option[value='']", count: 0

    patch library_banner_url(@library),
      params: { library: { banner_id: @other_banner.id } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal @other_banner, @library.reload.banner
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
        io: StringIO.new("PNG contents"),
        filename: "#{name.parameterize}.png",
        content_type: "image/png"
      )
      asset.save!
    end
  end
end
