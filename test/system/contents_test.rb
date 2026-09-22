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

  test "pagination preserves vertical scroll before the updated frame is painted" do
    20.times { |index| create_selection_content!(index) }

    visit contents_path
    assert_selector "tbody tr", count: 10
    page.execute_script("document.body.insertAdjacentHTML('afterbegin', '<div style=\"height: 1000px\"></div>')")

    page.execute_script(<<~JAVASCRIPT)
      document.addEventListener("click", () => {
        window.paginationClickScrollY = window.scrollY
      }, { capture: true, once: true })

      document.addEventListener("turbo:before-frame-render", (event) => {
        const render = event.detail.render
        event.detail.render = (currentFrame, newFrame) => {
          const result = render(currentFrame, newFrame)
          window.paginationRenderScrollY = window.scrollY
          return result
        }
      }, { once: true })
    JAVASCRIPT

    find("nav.pagy-bootstrap a.page-link", text: "2", exact_text: true).click

    assert_selector "nav.pagy-bootstrap a[aria-current='page']", text: "2", exact_text: true
    scroll_y = page.evaluate_script("window.paginationClickScrollY")
    assert_operator scroll_y, :>, 0
    assert_equal scroll_y, page.evaluate_script("window.paginationRenderScrollY")
    assert_equal scroll_y, page.evaluate_script("window.scrollY")
  end

  test "uploads and validates a file when it is selected" do
    @user.update!(role: :volunteer)
    visit contents_path
    click_on "New content"

    within "turbo-frame#modal" do
      fill_in "Title", with: "Early upload"
      fill_in "Display title", with: "Early upload display"
      fill_in "Description", with: "A file uploaded before the form is submitted"
      attach_file "File", file_fixture("document.pdf")

      assert_text "Uploaded and validated: document.pdf"
      assert_button "Create Content", disabled: false
      click_button "Create Content"
    end

    assert_text "Content was successfully created."
    assert_current_path contents_path
    content = Content.find_by!(title: "Early upload")
    assert_equal "document.pdf", content.file.filename.to_s
  end

  test "shows duplicate file validation before submission" do
    @user.update!(role: :volunteer)
    existing_content = @user.contents.build(
      title: "Existing upload",
      display_title: "Existing upload display",
      description: "Existing upload description"
    )
    File.open(file_fixture("document.pdf")) do |file|
      existing_content.file.attach(
        io: file,
        filename: "document.pdf",
        content_type: "application/pdf"
      )
      existing_content.save!
    end

    visit new_content_path
    attach_file "File", file_fixture("document.pdf")

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

  test "previews the next and previous content on the current page" do
    first = create_preview_content!("Preview row one", 2.days.ago)
    second = create_preview_content!("Preview row two", 1.day.ago)

    visit contents_path
    fill_in "Search", with: "Preview row"
    assert_selector "tbody tr", count: 2
    find("a[aria-label='Preview #{second.title}']").click

    within "turbo-frame#modal" do
      assert_text second.display_title
      assert_button "Previous", disabled: true
      click_on "Next"
      assert_text first.display_title
      assert_button "Next", disabled: true
      click_on "Previous"
      assert_text second.display_title
    end
  end

  test "edits content and replaces its file from the modal" do
    @user.update!(role: :intern_plus)
    content = create_preview_content!("Editable preview row", 1.day.ago)

    visit contents_path
    fill_in "Search", with: content.title
    find("a[aria-label='Edit #{content.title}']").click

    within "turbo-frame#modal" do
      assert_field "Title", with: content.title
      fill_in "Display title", with: "Updated preview display"
      attach_file "Choose New File", file_fixture("document.pdf")
      assert_text "Uploaded and validated: document.pdf"
      click_button "Update Content"
    end

    assert_text "Content was successfully updated."
    assert_equal "Updated preview display", content.reload.display_title
    assert_equal "document.pdf", content.file.filename.to_s
  end

  test "selects removes applies and clears a metadata filter" do
    metadata_type = metadata_types(:one)
    metadatum = Metadatum.find_by!(metadata_type:)
    matching_content = contents(:one)
    other_content = contents(:two)
    metadata_type.update!(name: "Subject")
    metadatum.update!(name: "History")
    matching_content.update_column(:title, "History content")
    other_content.update_column(:title, "Other content")
    component_id = "contents-filter-metadata-type-#{metadata_type.id}"

    visit contents_path
    click_button "Filters"

    within "##{component_id}" do
      fill_in "Subject", with: "Hist"
      assert_selector ".content-multi-select-dropdown.is-open"
      assert_button "History"
      assert_no_selector "button.list-group-item-success"
      click_button "History"
      assert_selector "##{component_id}-metadatum-#{metadatum.id}-badge", text: "History"
      assert_selector "##{component_id}-selector-#{metadatum.id}.active", text: "History"

      find("##{component_id}-metadatum-#{metadatum.id}-badge").click
      assert_no_selector "##{component_id}-metadatum-#{metadatum.id}-badge", visible: true
      assert_no_selector "input[value='#{metadatum.id}']:checked", visible: :all

      fill_in "Subject", with: "Hist"
      assert_button "History"
      click_button "History"
      assert_selector "input[value='#{metadatum.id}']:checked", visible: :all
    end

    submitted_filters = page.evaluate_script(<<~JAVASCRIPT)
      Array.from(new FormData(document.querySelector("#contents-advanced-filters form")).entries())
    JAVASCRIPT
    assert_includes submitted_filters, [
      "filters[metadata_type:#{metadata_type.id}][metadatum_ids][]",
      metadatum.id.to_s
    ]
    within "#contents-advanced-filters" do
      find("input[type='submit'][value='Apply Filters']").click
    end

    within "turbo-frame#contents_table" do
      assert_selector "tbody tr", count: 1
      assert_text matching_content.title
      assert_no_text other_content.title
    end

    within "#contents-advanced-filters" do
      click_button "Clear Filters"
      assert_no_selector "##{component_id}-metadatum-#{metadatum.id}-badge", visible: true
      assert_field "Subject", with: ""
      assert_no_selector "##{component_id}-list > *", visible: :all
    end

    within "turbo-frame#contents_table" do
      assert_text matching_content.title
      assert_text other_content.title
    end
  end

  test "animates the metadata dropdown and cancels closing when focus returns" do
    metadata_type = metadata_types(:one)
    component_id = "contents-filter-metadata-type-#{metadata_type.id}"
    search_id = "#{component_id}-search"

    visit contents_path
    click_button "Filters"

    within "##{component_id}" do
      find("##{search_id}").click
      assert_selector ".content-multi-select-dropdown.is-open"
    end

    closing_state = page.evaluate_async_script(<<~JAVASCRIPT)
      const done = arguments[0]
      const component = document.getElementById("#{component_id}")
      const input = document.getElementById("#{search_id}")
      const dropdown = component.querySelector("[data-content-multi-select-target='dropdown']")

      const observer = new MutationObserver(() => {
        if (dropdown.classList.contains("is-open")) return

        observer.disconnect()
        const remainedRendered = !dropdown.classList.contains("d-none")
        const onTransitionEnd = (event) => {
          if (event.propertyName !== "opacity") return

          dropdown.removeEventListener("transitionend", onTransitionEnd)
          done([remainedRendered, dropdown.classList.contains("d-none")])
        }
        dropdown.addEventListener("transitionend", onTransitionEnd)
      })

      observer.observe(dropdown, { attributes: true, attributeFilter: ["class"] })
      input.blur()
    JAVASCRIPT
    assert_equal [ true, true ], closing_state

    within "##{component_id}" do
      find("##{search_id}").click
      assert_selector ".content-multi-select-dropdown.is-open"
    end

    reopened_state = page.evaluate_async_script(<<~JAVASCRIPT)
      const done = arguments[0]
      const component = document.getElementById("#{component_id}")
      const input = document.getElementById("#{search_id}")
      const dropdown = component.querySelector("[data-content-multi-select-target='dropdown']")

      input.blur()
      window.setTimeout(() => input.focus(), 75)
      window.setTimeout(() => {
        done([dropdown.classList.contains("is-open"), dropdown.classList.contains("d-none")])
      }, 400)
    JAVASCRIPT
    assert_equal [ true, false ], reopened_state
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
      filename: "selection-#{index}.pdf",
      content_type: "application/pdf"
    )
    content.save!
    content.update_column(:created_at, (10 - index).days.ago)
    content
  end

  def create_preview_content!(title, created_at)
    content = @user.contents.build(
      title:,
      display_title: "#{title} display",
      description: "Content used to test previews"
    )
    content.file.attach(
      io: StringIO.new("preview bytes for #{title}"),
      filename: "#{title.parameterize}.pdf",
      content_type: "application/pdf"
    )
    content.save!
    content.update_column(:created_at, created_at)
    content
  end
end
