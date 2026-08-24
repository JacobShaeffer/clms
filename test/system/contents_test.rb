require "application_system_test_case"

class ContentsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(role: :organization)
    @user.active_shelves.delete_all
    @shelf = shelves(:one)
    ActiveShelf.activate!(user: @user, shelf: @shelf)
    sign_in @user
  end

  test "adds selected content while keeping the shelf dropdown open" do
    content = contents(:two)

    visit contents_path
    find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
    click_button "Shelves"
    check @shelf.name

    within ".shelf-selection-menu" do
      click_button "Add to Shelves"
      assert_text "Content was added to the selected shelves."
    end

    assert_selector ".shelf-selection-menu.show"
    assert_no_selector "input[data-content-table-selection-target='row']:checked"
    assert_no_selector "input[name='shelf_ids[]']:checked"
    assert ShelfContent.exists?(shelf: @shelf, content:)
  end

  test "table replacement does not retain selected rows" do
    content = contents(:one)

    visit contents_path
    find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
    find("thead a[aria-label='Sort Title ascending']").click

    assert_no_selector "input[data-content-table-selection-target='row']:checked"
  end

  test "column selection retains selected rows when the visible rows do not change" do
    content = contents(:one)

    visit contents_path
    find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
    click_button "Column select"
    check "Display title"

    assert_selector "thead th", text: "Display title"
    assert_selector "input[data-content-table-selection-target='row'][value='#{content.id}']:checked"
  end

  test "column selection clears selected rows when the visible rows change" do
    contents = 11.times.map { |index| create_selection_content!(index) }
    selected_content = contents.first
    still_visible_content = contents.second

    visit contents_path
    fill_in "Search", with: "Selection row"
    assert_selector "tbody tr", count: 10
    find("thead a[aria-label='Sort Title ascending']").click
    find("input[data-content-table-selection-target='row'][value='#{selected_content.id}']").check
    find("input[data-content-table-selection-target='row'][value='#{still_visible_content.id}']").check
    click_button "Column select"
    uncheck "Title"

    assert_no_selector "thead th", text: "Title"
    assert_no_selector "input[data-content-table-selection-target='row'][value='#{selected_content.id}']"
    assert_selector "input[data-content-table-selection-target='row'][value='#{still_visible_content.id}']:not(:checked)"
    assert_no_selector "input[data-content-table-selection-target='row']:checked"
  end

  test "uploads and validates a file when it is selected" do
    @user.update!(role: :volunteer)
    visit contents_path
    click_on "New content"

    within "turbo-frame#modal" do
      fill_in "Title", with: "Early upload"
      fill_in "Display title", with: "Early upload display"
      fill_in "Description", with: "A file uploaded before the form is submitted"
      attach_file "File", file_fixture("library_asset.png")

      assert_text "Uploaded and validated: library_asset.png"
      assert_button "Create Content", disabled: false
      click_button "Create Content"
    end

    assert_text "Content was successfully created."
    assert_current_path contents_path
    content = Content.find_by!(title: "Early upload")
    assert_equal "library_asset.png", content.file.filename.to_s
  end

  test "shows duplicate file validation before submission" do
    @user.update!(role: :volunteer)
    existing_content = @user.contents.build(
      title: "Existing upload",
      display_title: "Existing upload display",
      description: "Existing upload description"
    )
    File.open(file_fixture("library_asset.png")) do |file|
      existing_content.file.attach(
        io: file,
        filename: "library_asset.png",
        content_type: "image/png"
      )
      existing_content.save!
    end

    visit new_content_path
    attach_file "File", file_fixture("library_asset.png")

    assert_text "File already exists with title: Existing upload"
    assert_text "A file with the same filename already exists with title: Existing upload"
    assert_selector "[data-content-file-upload-target='status'] br", count: 1, visible: :all
    assert_button "Create Content", disabled: true
  end

  test "keeps validation errors in the new content modal" do
    @user.update!(role: :volunteer)
    visit contents_path
    click_on "New content"

    within "turbo-frame#modal" do
      click_button "Create Content"

      assert_selector ".alert.alert-danger", text: /prevented this content from being saved/
      assert_field "Title"
    end
    assert_current_path contents_path
  end

  private

  def create_selection_content!(index)
    content = @user.contents.build(
      title: "Selection row #{index.to_s.rjust(2, "0")}",
      display_title: "Selection row #{index}",
      description: "Content used to test table selection"
    )
    content.file.attach(
      io: StringIO.new("selection file #{index}"),
      filename: "selection-#{index}.png",
      content_type: "image/png"
    )
    content.save!
    content.update_column(:created_at, (10 - index).days.ago)
    content
  end
end
