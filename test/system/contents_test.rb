require "application_system_test_case"
require "tempfile"

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
      assert_selector ".modal-dialog.modal-fullscreen.content-view-dialog"
      assert_field "Title", with: second.title, disabled: true
      assert_selector ".modal-content > .modal-footer"
      assert_no_selector ".modal-body .modal-footer"
      assert_selector ".modal-title", text: second.title
      assert_button "Previous", disabled: true
      click_on "Next"
      assert_selector ".modal-title", text: first.title
      assert_button "Next", disabled: true
      click_on "Previous"
      assert_selector ".modal-title", text: second.title
    end
  end

  test "trashes restores and permanently deletes content" do
    @user.update!(role: :intern_plus)
    content = create_preview_content!("Trash workflow row", Time.current)

    visit contents_path
    find("a[aria-label='Preview #{content.title}']").click

    within "turbo-frame#modal" do
      click_link "Trash"
      assert_text "Move #{content.display_title} to Trash?"
      fill_in "Comment (optional)", with: "Needs administrator review"
      click_button "Move to Trash"
    end

    assert_text "Content was moved to Trash."
    assert_no_selector "a[aria-label='Preview #{content.title}']"
    assert_equal "Needs administrator review", content.reload.trash_comment

    @user.update!(role: :admin)
    visit trash_contents_path

    assert_text content.title
    assert_text "Needs administrator review"
    within "##{ActionView::RecordIdentifier.dom_id(content, :trash)}" do
      click_button "Restore"
    end

    assert_text "Content was restored."
    refute content.reload.trashed?
    assert_nil content.trash_comment

    content.trash!(comment: "Delete permanently")
    visit trash_contents_path
    within "##{ActionView::RecordIdentifier.dom_id(content, :trash)}" do
      accept_confirm("Permanently delete #{content.title}? This cannot be undone.") do
        click_button "Delete permanently"
      end
    end

    assert_text "Content was permanently deleted."
    refute Content.exists?(content.id)
  end

  test "returns to the content view after updating or canceling an edit" do
    @user.update!(role: :volunteer)
    content = create_preview_content!("View edit row", 2.days.ago)
    following_content = create_preview_content!("View edit next row", 1.day.ago)

    visit contents_path
    fill_in "Search", with: "View edit"
    assert_selector "tbody tr", count: 2
    find("a[aria-label='Preview #{following_content.title}']").click

    within "turbo-frame#modal" do
      click_on "Edit"
      assert_selector ".modal-title", text: "Edit content"
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("window.bootstrap.Modal.getInstance(document.querySelector('#modal .modal'))?._isTransitioning === false")
      end
      fill_in "Title", with: "Updated view title", fill_options: { clear: :backspace }
      fill_in "Description", with: "Updated view description", fill_options: { clear: :backspace }
      click_button "Update Content"
      assert_selector ".modal-title", text: "Updated view title"
      assert_field "Title", with: "Updated view title", disabled: true
      assert_field "Description", with: "Updated view description", disabled: true

      click_on "Edit"
      assert_selector ".modal-title", text: "Edit content"
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("window.bootstrap.Modal.getInstance(document.querySelector('#modal .modal'))?._isTransitioning === false")
      end
      fill_in "Title", with: "Unsaved title", fill_options: { clear: :backspace }
      click_on "Cancel"
      assert_selector ".modal-title", text: "Updated view title"
      assert_field "Title", with: "Updated view title", disabled: true

      click_on "Edit"
      find(".modal-header [aria-label='Close']").click
      assert_selector ".modal-title", text: "Updated view title"
      click_on "Next"
      assert_selector ".modal-title", text: content.title
    end
    assert_equal "Updated view title", following_content.reload.title
  end

  test "edits content and replaces its file from the modal" do
    @user.update!(role: :intern_plus)
    content = create_preview_content!("Editable preview row", 1.day.ago)

    visit contents_path
    fill_in "Search", with: content.title
    find("a[aria-label='Edit #{content.title}']").click

    within "turbo-frame#modal" do
      assert_field "Title", with: content.title
      original_preview_url = find(".content-edit-preview iframe.content-preview-pdf")[:src]
      fill_in "Display title",
        with: "Updated preview display",
        fill_options: { clear: :backspace }
      attach_file "Choose New File", file_fixture("document.pdf")
      assert_selector ".content-edit-preview iframe.content-preview-pdf[src^='blob:']"
      refute_equal original_preview_url, find(".content-edit-preview iframe.content-preview-pdf")[:src]
      assert_text "Uploaded and validated: document.pdf"
      click_button "Update Content"
    end

    assert_text "Content was successfully updated."
    assert_equal "Updated preview display", content.reload.display_title
    assert_equal "document.pdf", content.file.filename.to_s
  end

  test "switches replacement previews and restores the saved preview when cleared" do
    @user.update!(role: :intern_plus)
    content = create_preview_content!("Changing preview row", 1.day.ago)

    visit contents_path
    fill_in "Search", with: content.title
    find("a[aria-label='Edit #{content.title}']").click

    within "turbo-frame#modal" do
      original_preview_url = find(".content-edit-preview iframe.content-preview-pdf")[:src]

      with_temporary_media_file(".mp3", "ID3\x04\x00\x00\x00\x00\x00\x00".b) do |path|
        attach_file "Choose New File", path
        assert_selector ".content-edit-preview audio.content-preview-audio source[type='audio/mpeg'][src^='blob:']",
          visible: :all
        assert_text "Uploaded and validated:"
      end

      with_temporary_media_file(".mp4", [ 0, 0, 0, 24 ].pack("C*") + "ftypisom\x00\x00\x02\x00isomiso2".b) do |path|
        attach_file "Choose New File", path
        assert_no_selector ".content-edit-preview audio"
        assert_selector ".content-edit-preview video.content-preview-video source[type='video/mp4'][src^='blob:']",
          visible: :all
        assert_text "Uploaded and validated:"
      end

      file_input = find("#content_file", visible: :all)
      page.execute_script(<<~JAVASCRIPT, file_input)
        arguments[0].value = ""
        arguments[0].dispatchEvent(new Event("change", { bubbles: true }))
      JAVASCRIPT

      assert_selector ".content-edit-preview iframe.content-preview-pdf"
      assert_equal original_preview_url, find(".content-edit-preview iframe.content-preview-pdf")[:src]
      assert_button "Update Content", disabled: false
    end
  end

  test "restores the saved preview when replacement validation fails" do
    @user.update!(role: :intern_plus)
    content = create_preview_content!("Rejected preview row", 1.day.ago)
    duplicate = @user.contents.build(
      title: "Existing document",
      display_title: "Existing document display",
      description: "Content with the replacement file"
    )
    File.open(file_fixture("document.pdf")) do |file|
      duplicate.file.attach(io: file, filename: "document.pdf", content_type: "application/pdf")
      duplicate.save!
    end

    visit contents_path
    fill_in "Search", with: content.title
    find("a[aria-label='Edit #{content.title}']").click

    within "turbo-frame#modal" do
      original_preview_url = find(".content-edit-preview iframe.content-preview-pdf")[:src]
      attach_file "Choose New File", file_fixture("document.pdf")

      assert_text "File already exists with title: Existing document"
      assert_selector ".content-edit-preview iframe.content-preview-pdf"
      assert_equal original_preview_url, find(".content-edit-preview iframe.content-preview-pdf")[:src]
      assert_no_selector ".content-edit-preview [src^='blob:']"
      assert_button "Update Content", disabled: true
    end
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

  def with_temporary_media_file(extension, bytes)
    Tempfile.create([ "content-preview", extension ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield file.path
    end
  end

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
