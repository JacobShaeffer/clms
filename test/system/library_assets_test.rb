require "application_system_test_case"

class LibraryAssetsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(role: :intern_plus)
    sign_in users(:one)
  end

  test "combines search with independent language and type toggles" do
    english_banner = create_asset!("English Guide Banner", "English", "Banner")
    english_module = create_asset!("English Guide Module", "English", "Module")
    french_module = create_asset!("French Guide Module", "French", "Module")
    visit library_assets_path

    [ "Language", "Type" ].each do |group|
      within "fieldset[aria-label='#{group}']" do
        assert_selector "button.active[aria-pressed='true']", text: "All"
      end
    end
    fill_in "Search by name", with: "guide"
    assert_selector "#library_assets > .col", count: 3
    within "fieldset[aria-label='Language']" do
      click_button "English"
      assert_selector "button.active[aria-pressed='true']", text: "English"
    end
    assert_selector "#library_assets > .col", count: 2
    within "fieldset[aria-label='Type']" do
      click_button "Module"
    end
    assert_selector "#library_assets > .col", count: 1
    assert_selector "#library_assets .card-title", text: english_module.name
    assert_no_selector "#library_assets .card-title", text: english_banner.name

    within "fieldset[aria-label='Language']" do
      click_button "French"
    end
    assert_selector "#library_assets .card-title", text: french_module.name
    within "fieldset[aria-label='Type']" do
      assert_selector "button.active[aria-pressed='true']", text: "Module"
      click_button "All"
    end
    within "fieldset[aria-label='Language']" do
      assert_selector "button.active[aria-pressed='true']", text: "French"
      click_button "All"
    end
    assert_selector "#library_assets > .col", count: 3
    assert_field "Search by name", with: "guide"
    fill_in "Search by name", with: ""
    assert_selector "#library_assets > .col", count: LibraryAsset.count
  end

  test "creating and editing assets keeps the selected filters active" do
    visit library_assets_path
    within "fieldset[aria-label='Language']" do
      click_button "English"
    end
    within "fieldset[aria-label='Type']" do
      click_button "Module"
    end
    assert_text "No library assets match your search and filters."
    click_on "New library asset"
    within "#modal" do
      fill_in "Name", with: "Filtered Guide"
      fill_in "Language", with: "English"
      select "Module", from: "Type"
      attach_file "Image (PNG)", file_fixture("library_asset.png")
      click_button "Create Library asset"
    end
    assert_selector "#library_assets > .col", count: 1
    assert_selector "#library_assets .card-title", text: "Filtered Guide"
    within "#library_assets" do
      click_on "Edit"
    end
    within "#modal" do
      fill_in "Language", with: "French"
      click_button "Update Library asset"
    end
    assert_no_selector "#library_assets > .col"
    assert_text "No library assets match your search and filters."
    within "fieldset[aria-label='Language']" do
      assert_selector "button.active[aria-pressed='true']", text: "English"
    end
    within "fieldset[aria-label='Type']" do
      assert_selector "button.active[aria-pressed='true']", text: "Module"
    end
  end

  test "deleting the last filtered asset keeps filters and shows empty results" do
    asset = create_asset!("English Guide", "English", "Module")
    visit library_assets_path(q: "guide", language: "English", asset_type: "Module")
    within "#library_assets" do
      click_on "Destroy"
    end
    within "#modal" do
      click_button "Delete"
    end
    assert_no_selector "#modal .modal"
    assert_no_selector "#library_assets > .col"
    assert_text "No library assets match your search and filters."
    assert_field "Search by name", with: "guide"
    refute LibraryAsset.exists?(asset.id)
  end

  test "creates an image-only asset and edits its optional language and type" do
    visit library_assets_path
    click_on "New library asset"
    within "#modal" do
      attach_file "Image (PNG)", file_fixture("library_asset.png")
      click_button "Create Library asset"
    end
    assert_no_selector "#modal .modal"
    assert_selector "#library_assets .card-title", text: "library_asset.png"
    asset = LibraryAsset.last
    refute asset.design_files.attached?

    within "##{ActionView::RecordIdentifier.dom_id(asset, :listing)}" do
      click_on "Edit"
    end
    within "#modal" do
      assert_selector "input#library_asset_language[list='library-asset-languages']"
      fill_in "Language", with: "French"
      select "Module", from: "Type"
      click_button "Update Library asset"
    end
    assert_no_selector "#modal .modal"
    within "##{ActionView::RecordIdentifier.dom_id(asset, :listing)}" do
      assert_text "French"
      assert_text "Module"
    end
    assert_equal "French", asset.reload.language
    assert_equal "Module", asset.asset_type
  end

  private

  def create_asset!(name, language, asset_type)
    LibraryAsset.new(user: users(:one), name:, language:, asset_type:).tap do |asset|
      asset.image.attach(
        io: StringIO.new(file_fixture("library_asset.png").read),
        filename: "#{name.parameterize}.png", content_type: "image/png"
      )
      asset.save!
    end
  end
end
