require "test_helper"
require "stringio"
require "uri"

class ContentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  CONTENTS_TABLE_KEY = "contents.index"
  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  TURBO_STREAM_HEADERS = TURBO_FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html").freeze

  self.fixture_table_names = []

  setup do
    Content.destroy_all

    @user = User.create!(
      name: "Filter User",
      email: "filter-user@example.com",
      password: "password",
      role: :volunteer
    )
    sign_in @user

    @metadata_type = MetadataType.create!(
      name: "Subject",
      order: 1,
      user: @user
    )
    @history = Metadatum.create!(
      name: "History",
      metadata_type: @metadata_type,
      user: @user,
      under_review: false
    )
    @science = Metadatum.create!(
      name: "Science",
      metadata_type: @metadata_type,
      user: @user,
      under_review: false
    )

    @matching_content = create_content!(
      title: "River Archive",
      display_title: "Display Match",
      description: "Hydrology field notes"
    )
    @other_content = create_content!(
      title: "Mountain File",
      display_title: "Display Miss",
      description: "Geology field notes"
    )
    @matching_content.metadata << @history
    @other_content.metadata << @science
  end

  test "index renders row selection and the active shelf dropdown" do
    first_shelf = @user.shelves.create!(name: "First shelf")
    second_shelf = @user.shelves.create!(name: "Second shelf")
    ActiveShelf.prepend!(user: @user, shelf: first_shelf)
    ActiveShelf.prepend!(user: @user, shelf: second_shelf)

    get contents_url

    assert_response :success
    assert_select "[data-controller='content-table-selection']"
    assert_select "thead input[type='checkbox'][data-content-table-selection-target='page']", count: 1
    assert_select "tbody input[type='checkbox'][name='content_ids[]'][form='contents-add-to-shelves-form']", count: 2
    assert_select "button.dropdown-toggle[data-bs-auto-close='false']", text: "Shelves"
    assert_select "form#contents-add-to-shelves-form[action='#{add_to_shelves_contents_path}']" do
      assert_select "input[name='shelf_ids[]']", count: 2
      assert_select "label", text: second_shelf.name
      assert_select "label", text: first_shelf.name
      assert_select "input[type='submit'][value='Add to Shelves']:not([disabled])"
      assert_select "#contents-add-to-shelves-status[role='status']"
    end
  end

  test "add to shelves creates missing placements and skips existing ones" do
    first_shelf = @user.shelves.create!(name: "First shelf")
    second_shelf = @user.shelves.create!(name: "Second shelf")
    ActiveShelf.activate!(user: @user, shelf: first_shelf)
    ActiveShelf.activate!(user: @user, shelf: second_shelf)
    ShelfContent.create!(shelf: first_shelf, content: @matching_content)

    assert_difference("ShelfContent.count", 3) do
      post add_to_shelves_contents_url,
        params: {
          content_ids: [ @matching_content.id, @other_content.id ],
          shelf_ids: [ first_shelf.id, second_shelf.id ]
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal [ @matching_content.id, @other_content.id ].sort, first_shelf.contents.ids.sort
    assert_equal [ @matching_content.id, @other_content.id ].sort, second_shelf.contents.ids.sort
    assert_select "turbo-stream[action='replace'][target='contents_table']" do
      assert_select "input[name='content_ids[]'][checked]", count: 0
    end
    assert_select "turbo-stream[action='replace'][target='contents-add-to-shelves-form']" do
      assert_select "form#contents-add-to-shelves-form"
      assert_select "input[name='shelf_ids[]'][checked]", count: 0
    end
    assert_select "turbo-stream[action='update'][target='contents-add-to-shelves-status']",
      text: /Existing placements were skipped/

    assert_no_difference("ShelfContent.count") do
      post add_to_shelves_contents_url,
        params: {
          content_ids: [ @matching_content.id, @other_content.id ],
          shelf_ids: [ first_shelf.id, second_shelf.id ]
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_select "turbo-stream[action='update'][target='contents-add-to-shelves-status']",
      text: /already on the selected shelves/
  end

  test "add to shelves rejects empty stale and foreign selections" do
    active_shelf = @user.shelves.create!(name: "Active shelf")
    archived_shelf = @user.shelves.create!(name: "Archived shelf")
    foreign_user = User.create!(
      name: "Foreign User",
      email: "foreign-user@example.com",
      password: "password",
      role: :organization
    )
    foreign_shelf = foreign_user.shelves.create!(name: "Foreign shelf")
    ActiveShelf.activate!(user: @user, shelf: active_shelf)
    ActiveShelf.activate!(user: foreign_user, shelf: foreign_shelf)

    assert_no_difference("ShelfContent.count") do
      post add_to_shelves_contents_url,
        params: { content_ids: [], shelf_ids: [] },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[target='contents-add-to-shelves-status']", text: /Select at least one/

    [ archived_shelf, foreign_shelf ].each do |invalid_shelf|
      assert_no_difference("ShelfContent.count") do
        post add_to_shelves_contents_url,
          params: { content_ids: [ @matching_content.id ], shelf_ids: [ invalid_shelf.id ] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :unprocessable_content
      assert_select "turbo-stream[target='contents-add-to-shelves-status']", text: /no longer active/
    end
  end

  test "index renders table state controls" do
    get contents_url

    assert_response :success
    assert_select "h1", text: "Contents"
    assert_select "h1.title", count: 0
    assert_select "a.btn.btn-primary[data-turbo-frame='modal']", text: "New content"
    assert_select "turbo-frame#contents_table"
    assert_select "turbo-frame#contents_table input[name='q']", count: 0
    assert_select "form[action='#{table_contents_path}'][data-turbo-frame='contents_table'] input.form-control[name='q']"
    assert_select "button.btn.btn-secondary[data-bs-toggle='offcanvas'][data-bs-target='#contents-advanced-filters']", text: "Filters"
    assert_select ".offcanvas.offcanvas-end#contents-advanced-filters"
    assert_select "#contents-advanced-filters-title.offcanvas-title", text: "Filters"
    assert_select ".offcanvas-header > button.btn-close[data-bs-dismiss='offcanvas']"
    assert_select ".offcanvas-body section h3", text: "General Filters"
    assert_select ".offcanvas-body section h3", text: "Metadata Filters"
    assert_select ".offcanvas-body section:last-of-type h3", text: "Advanced Filters"
    assert_select ".offcanvas-body section:last-of-type button.collapsed[data-bs-toggle='collapse'][data-bs-target='#contents-advanced-filters-fields'][aria-expanded='false']", text: "Advanced Filters"
    assert_select ".offcanvas-body section:last-of-type #contents-advanced-filters-fields.collapse:not(.show)"
    assert_select ".offcanvas-body input.form-control[name='filters[title][value]']"
    metadata_filter_id = "contents-filter-metadata-type-#{@metadata_type.id}"
    assert_select "##{metadata_filter_id}[data-controller='content-multi-select']" \
      "[data-content-multi-select-selection-context-value='filter']" \
      "[data-content-multi-select-allow-create-value='false']"
    assert_select "##{metadata_filter_id}-search[placeholder='Search']"
    assert_select "##{metadata_filter_id} .content-multi-select-dropdown.d-none" \
      "[data-content-multi-select-target='dropdown']" do
      assert_select "##{metadata_filter_id}-list.content-multi-select-list.list-group" \
        "[data-content-multi-select-target='list']"
    end
    assert_select "input[name='filters[metadata_type:#{@metadata_type.id}][metadatum_ids][]']", count: 0
    assert_select ".offcanvas-body section:last-of-type" do
      assert_select "input.form-control[name='filters[created_at][from]']"
      assert_select "input.form-control[name='filters[created_at][to]']"
      assert_select "input.form-control[name='filters[updated_at][from]']"
      assert_select "input.form-control[name='filters[updated_at][to]']"
      assert_select "input.form-control[name='filters[description][value]']"
      assert_select "input.form-control[name='filters[additional_notes][value]']"
    end
    assert_select ".offcanvas-body input.btn.btn-primary[type='submit'][value='Apply Filters']", count: 1
    assert_select ".offcanvas-body button.btn.btn-secondary[name='clear_filters']", text: "Clear Filters"
    assert_select "turbo-frame#contents_table .table-responsive > table.table.table-striped.align-middle"
    assert_select "turbo-frame#contents_table .row.align-items-center form[action='#{table_contents_path}']" do
      assert_select "select.form-select[name='per_page']"
    end
    assert_select "turbo-frame#contents_table .row.align-items-center > .col-auto.ms-auto form.d-flex.align-items-center"
    assert_select "thead tr th:last-child.content-table-actions", text: "Actions"
    assert_select "tbody tr .content-table-actions" do
      assert_select "a[aria-label^='Preview '][data-turbo-frame='modal']", minimum: 1
      assert_select "a[aria-label^='Edit '][data-turbo-frame='modal']", minimum: 1
    end
  end

  test "organization users see previews but not edit actions" do
    @user.update!(role: :organization)

    get contents_url

    assert_response :success
    assert_select "thead tr th:last-child.content-table-actions", text: "Actions"
    assert_select "a[aria-label^='Preview ']", count: 2
    assert_select "a[aria-label^='Edit ']", count: 0
  end

  test "show renders PDF audio and video previews in the modal" do
    audio = create_content!(
      title: "Audio preview",
      display_title: "Audio display",
      description: "Audio description",
      filename: "audio-preview.mp3",
      content_type: "audio/mpeg",
      bytes: "audio preview bytes"
    )
    video = create_content!(
      title: "Video preview",
      display_title: "Video display",
      description: "Video description",
      filename: "video-preview.mp4",
      content_type: "video/mp4",
      bytes: "video preview bytes"
    )

    get content_url(@matching_content), headers: TURBO_FRAME_HEADERS
    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: @matching_content.display_title
    assert_select "iframe.content-preview-pdf[src*='/rails/active_storage/blobs/']", count: 1

    get content_url(audio), headers: TURBO_FRAME_HEADERS
    assert_select "audio.content-preview-audio[controls] source[type='audio/mpeg'][src*='/rails/active_storage/blobs/']", count: 1

    get content_url(video), headers: TURBO_FRAME_HEADERS
    assert_select "video.content-preview-video[controls] source[type='video/mp4'][src*='/rails/active_storage/blobs/']", count: 1
  end

  test "preview navigation follows the current ordered page and stops at its boundaries" do
    @matching_content.update!(title: "Alpha preview")
    @other_content.update!(title: "Bravo preview")

    get table_contents_url, params: {
      q: "preview",
      sort_column: "title",
      sort_state: "default"
    }

    preview_links = css_select("tbody a[aria-label^='Preview ']")
    assert_equal 2, preview_links.size

    get preview_links.first["href"], headers: TURBO_FRAME_HEADERS
    assert_select ".modal-title", text: @matching_content.display_title
    assert_select "button[disabled]", text: "Previous"
    next_link = css_select("a").find { |link| link.text.strip == "Next" }
    assert next_link

    get next_link["href"], headers: TURBO_FRAME_HEADERS
    assert_select ".modal-title", text: @other_content.display_title
    assert_select "a", text: "Previous"
    assert_select "button[disabled]", text: "Next"
  end

  test "preview navigation does not cross a Pagy page" do
    create_paginated_contents!(9)

    get table_contents_url, params: { page: 2 }

    preview_link = css_select("tbody a[aria-label^='Preview ']").first
    assert preview_link
    assert_select "tbody tr", count: 1

    get preview_link["href"], headers: TURBO_FRAME_HEADERS
    assert_select "button[disabled]", text: "Previous"
    assert_select "button[disabled]", text: "Next"
  end

  test "preview ignores navigation signed for another user or changed by the client" do
    token = ContentTables::PageNavigation.token_for(
      user: @user,
      records: [ @matching_content, @other_content ]
    )

    get content_url(@matching_content, navigation: "#{token}changed"), headers: TURBO_FRAME_HEADERS
    assert_select "button[disabled]", text: "Previous"
    assert_select "button[disabled]", text: "Next"

    other_user = User.create!(
      name: "Preview User",
      email: "preview-user@example.com",
      password: "password",
      role: :organization
    )
    sign_in other_user
    get content_url(@matching_content, navigation: token), headers: TURBO_FRAME_HEADERS
    assert_select "button[disabled]", text: "Previous"
    assert_select "button[disabled]", text: "Next"
  end

  test "new renders a Bootstrap content form" do
    get new_content_url

    assert_response :success
    assert_select "h1", text: "New content"
    assert_select "h1.title", count: 0
    assert_select "form[action='#{contents_path}'][method='post'][data-turbo-frame='_top'][data-controller='content-file-upload']" do
      assert_select "label.form-label[for='content_title']", text: "Title"
      assert_select "input.form-control#content_title[name='content[title]']"
      assert_select "textarea.form-control#content_description[name='content[description]']"
      assert_select "input[type='file'][name='content[file]'][accept='application/pdf,audio/mpeg,video/mp4,.pdf,.mp3,.mp4'][data-action='change->content-file-upload#upload']"
      assert_select "input.btn.btn-primary[type='submit'][data-content-file-upload-target='submit']"
      assert_select "a.btn.btn-secondary[href='#{contents_path}']", text: "Cancel"
    end
  end

  test "edit prefills content and metadata while hiding the file picker below delete level" do
    @matching_content.metadata << @science

    get edit_content_url(@matching_content), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Edit content"
    assert_select "form[action='#{content_path(@matching_content)}'][data-turbo-frame='modal']" do
      assert_select "input[name='content[title]'][value='#{@matching_content.title}']"
      assert_select "textarea[name='content[description]']", text: @matching_content.description
      assert_select "#content-form-metadata-type-#{@metadata_type.id}-metadatum-#{@history.id}-badge", text: @history.name
      assert_select "#content-form-metadata-type-#{@metadata_type.id}-metadatum-#{@science.id}-badge", text: @science.name
      assert_select "input[type='file'][name='content[file]']", count: 0
    end
  end

  test "intern plus edit shows an optional Choose New File picker" do
    @user.update!(role: :intern_plus)

    get edit_content_url(@matching_content), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "label[for='content_file']", text: "Choose New File"
    assert_select "input#content_file[type='file'][name='content[file]']"
    assert_select "[data-content-file-upload-required-value='false']"
    assert_select "[data-content-file-upload-target='status']", text: /Current file:/
  end

  test "update changes content fields and keeps the current file when no file is submitted" do
    original_blob = @matching_content.file.blob

    patch content_url(@matching_content), params: {
      content: {
        title: "Updated title",
        display_title: "Updated display",
        description: "Updated description",
        metadatum_ids: [ @science.id ]
      }
    }

    assert_redirected_to contents_path
    @matching_content.reload
    assert_equal "Updated title", @matching_content.title
    assert_equal [ @science.id ], @matching_content.metadatum_ids
    assert_equal original_blob, @matching_content.file.blob
  end

  test "invalid modal update rerenders the edit modal with errors" do
    patch content_url(@matching_content),
      params: { content: { title: "", description: "" } },
      headers: TURBO_STREAM_HEADERS

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".modal-title", text: "Edit content"
      assert_select ".alert.alert-danger", text: /prevented this content from being saved/
    end
  end

  test "file validation and replacement require delete-level permission" do
    assert_no_difference("ActiveStorage::Blob.count") do
      post validate_file_content_url(@matching_content), params: {
        file: Rack::Test::UploadedFile.new(
          StringIO.new("replacement bytes"),
          "application/pdf",
          original_filename: "replacement.pdf"
        )
      }, as: :multipart
    end
    assert_redirected_to root_path

    original_blob = @matching_content.file.blob
    patch content_url(@matching_content), params: {
      content: { file: @other_content.file.blob.signed_id }
    }
    assert_redirected_to root_path
    assert_equal original_blob, @matching_content.reload.file.blob
  end

  test "intern plus can validate and replace an existing file" do
    @user.update!(role: :intern_plus)
    original_blob = @matching_content.file.blob

    post validate_file_content_url(@matching_content), params: {
      file: Rack::Test::UploadedFile.new(
        StringIO.new("replacement file bytes"),
        "application/pdf",
        original_filename: "replacement.pdf"
      )
    }, as: :multipart

    assert_response :success
    signed_id = response.parsed_body.fetch("signed_id")
    assert_equal original_blob, @matching_content.reload.file.blob

    patch content_url(@matching_content), params: {
      content: { file: signed_id }
    }

    assert_redirected_to contents_path
    assert_equal "replacement.pdf", @matching_content.reload.file.filename.to_s
    refute_equal original_blob, @matching_content.file.blob
  end

  test "new renders a form targeting the modal when requested in the modal frame" do
    get new_content_url, headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal form[data-turbo-frame='modal']"
  end

  test "invalid modal submission rerenders errors inside the modal" do
    assert_no_difference("Content.count") do
      post contents_url,
        params: { content: { title: "", display_title: "", description: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='modal'] template turbo-frame#modal" do
      assert_select ".alert.alert-danger", text: /prevented this content from being saved/
      assert_select "form[data-turbo-frame='modal']"
    end
  end

  test "validate file uploads a supported file and returns its signed id" do
    assert_difference("ActiveStorage::Blob.count", 1) do
      post validate_file_contents_url, params: {
        file: Rack::Test::UploadedFile.new(
          StringIO.new("PDF contents"),
          "application/pdf",
          original_filename: "document.pdf"
        )
      }, as: :multipart
    end

    assert_response :success
    response_body = response.parsed_body
    blob = ActiveStorage::Blob.find_signed!(response_body.fetch("signed_id"))
    assert_equal "document.pdf", response_body.fetch("filename")
    assert_equal "document.pdf", blob.filename.to_s
    assert ActiveStorage::Blob.unattached.exists?(blob.id)
  end

  test "validate file returns model errors and purges an unsupported file" do
    assert_no_difference("ActiveStorage::Blob.count") do
      post validate_file_contents_url, params: {
        file: fixture_file_upload("library_asset.png", "image/png")
      }, as: :multipart
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body.fetch("errors"), "must be a supported file type"
  end

  test "validate file returns duplicate filename and checksum model errors" do
    existing_file = @matching_content.file.blob

    assert_no_difference("ActiveStorage::Blob.count") do
      post validate_file_contents_url, params: {
        file: Rack::Test::UploadedFile.new(
          StringIO.new(existing_file.download),
          existing_file.content_type,
          original_filename: existing_file.filename.to_s.upcase
        )
      }, as: :multipart
    end

    assert_response :unprocessable_content
    errors = response.parsed_body.fetch("errors")
    assert_includes errors, "File already exists with title: #{@matching_content.title}"
    assert_includes errors, "A file with the same filename already exists with title: #{@matching_content.title}"
  end

  test "validate file requires create permission" do
    @user.update!(role: :guest)

    assert_no_difference("ActiveStorage::Blob.count") do
      post validate_file_contents_url, params: {
        file: Rack::Test::UploadedFile.new(
          StringIO.new("PDF contents"),
          "application/pdf",
          original_filename: "document.pdf"
        )
      }, as: :multipart
    end

    assert_redirected_to root_path
  end

  test "create accepts a validated signed blob and preserves it after other validation errors" do
    post validate_file_contents_url, params: {
      file: Rack::Test::UploadedFile.new(
        StringIO.new("PDF contents"),
        "application/pdf",
        original_filename: "document.pdf"
      )
    }, as: :multipart
    signed_id = response.parsed_body.fetch("signed_id")

    post contents_url, params: {
      content: {
        title: "",
        display_title: "Uploaded display title",
        description: "Uploaded description",
        file: signed_id
      }
    }

    assert_response :unprocessable_content
    assert_select "input[type='hidden'][name='content[file]'][value='#{signed_id}']"

    assert_difference("Content.count", 1) do
      post contents_url, params: {
        content: {
          title: "Signed upload",
          display_title: "Uploaded display title",
          description: "Uploaded description",
          file: signed_id
        }
      }
    end

    assert_redirected_to contents_path
    assert_equal "document.pdf", Content.find_by!(title: "Signed upload").file.filename.to_s
  end

  test "new lists metadata types in display order" do
    earlier_type = MetadataType.create!(name: "Audience", order: 0, user: @user)

    get new_content_url

    labels = css_select("[data-controller='content-multi-select'] > label").map(&:text)
    assert_equal MetadataType.in_display_order.pluck(:name), labels
    assert_operator labels.index(earlier_type.name), :<, labels.index(@metadata_type.name)
  end

  test "new renders metadata search groups without selecting every available value" do
    get new_content_url

    assert_response :success
    assert_select "[data-controller='content-multi-select'][data-content-multi-select-type-value='#{@metadata_type.id}']"
    assert_select "input[name='content[metadatum_ids][]']", count: 0
  end

  test "failed create restores the selected metadata badges" do
    post contents_url, params: {
      content: {
        title: "",
        display_title: "",
        description: "",
        metadatum_ids: [ @history.id ]
      }
    }

    assert_response :unprocessable_content
    component_id = "content-form-metadata-type-#{@metadata_type.id}"
    assert_select "##{component_id}-metadatum-#{@history.id}-badge", text: @history.name
    assert_select "input##{component_id}-metadatum-#{@history.id}[checked][value='#{@history.id}']"
    assert_select "##{component_id}-metadatum-#{@science.id}-badge", count: 0
  end

  test "metadata search returns matching values and marks selected values active" do
    component_id = "test-content-metadata-type-#{@metadata_type.id}"
    get search_contents_url,
      params: {
        target: "#{component_id}-list",
        metadata_type_id: @metadata_type.id,
        component_id:,
        selection_context: "content",
        allow_create: "1",
        search: "Hist",
        selected_ids: @history.id.to_s,
        metadatum_count: 10
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='update'][target='#{component_id}-list']"
    assert_select "button##{component_id}-selector-#{@history.id}.active", text: @history.name
    assert_select "button", text: @science.name, count: 0
    assert_select "button.list-group-item-success", text: /Add.*Hist/
  end

  test "permitted table users can search filter metadata without a creation action" do
    @history.update!(under_review: true)
    component_id = "contents-filter-metadata-type-#{@metadata_type.id}"

    %i[organization volunteer intern intern_plus admin].each do |role|
      @user.update!(role:)
      get search_contents_url,
        params: {
          target: "#{component_id}-list",
          metadata_type_id: @metadata_type.id,
          component_id:,
          selection_context: "filter",
          allow_create: "0",
          search: "Hist",
          selected_ids: "",
          metadatum_count: 10
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_select "button##{component_id}-selector-#{@history.id}", text: @history.name
      assert_select "button.list-group-item-success", count: 0
    end

    @user.update!(role: :organization)
    get add_existing_metadatum_contents_url,
      params: {
        target: "#{component_id}-badges",
        metadata_type_id: @metadata_type.id,
        metadatum_id: @history.id,
        component_id:,
        selection_context: "filter"
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "turbo-stream[action='append'][target='#{component_id}-badges']"
    assert_select "input[name='filters[metadata_type:#{@metadata_type.id}][metadatum_ids][]']" \
      "[value='#{@history.id}'][checked]"
  end

  test "authorized users can add and select a new metadatum" do
    component_id = "content-form-metadata-type-#{@metadata_type.id}"
    assert_difference "Metadatum.count", 1 do
      post add_new_metadatum_contents_url,
        params: {
          target: "#{component_id}-badges",
          metadata_type_id: @metadata_type.id,
          component_id:,
          selection_context: "content",
          name: "  Geography  "
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    metadatum = Metadatum.find_by!(name: "Geography")
    assert metadatum.under_review?
    assert_select "turbo-stream[action='append'][target='#{component_id}-badges']"
    assert_select "##{component_id}-metadatum-#{metadatum.id}-badge", text: metadatum.name
  end

  test "table action renders only the contents table frame" do
    get table_contents_url, params: { q: "river" }

    assert_response :success
    assert_select "turbo-frame#contents_table"
    assert_select "button", text: "Advanced Filters", count: 0
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title
  end

  test "per page persists after search update" do
    11.times do |index|
      create_content!(
        title: "River Extra #{index}",
        display_title: "Extra #{index}",
        description: "Hydrology field notes"
      )
    end

    get table_contents_url, params: { per_page: 20 }
    get table_contents_url, params: { q: "River" }

    assert_response :success
    assert_select "tbody tr", 12
  end

  test "columns persist after per page update" do
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "display_title" ]
    }
    get table_contents_url, params: { per_page: 20 }

    assert_response :success
    assert_select "th", text: "Display title"
    assert_includes @response.body, @matching_content.display_title
  end

  test "advanced filters persist after per page update" do
    get table_contents_url, params: {
      filters: {
        "description" => { "value" => "hydrology" }
      }
    }
    get table_contents_url, params: { per_page: 20 }

    assert_response :success
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title
  end

  test "metadata filters persist in the table preference" do
    get table_contents_url, params: {
      filters: {
        "metadata_type:#{@metadata_type.id}" => { "metadatum_ids" => [ @history.id ] }
      }
    }
    get table_contents_url, params: { per_page: 20 }

    assert_response :success
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title

    get contents_url

    component_id = "contents-filter-metadata-type-#{@metadata_type.id}"
    assert_select "##{component_id}-metadatum-#{@history.id}-badge", text: @history.name
    assert_select "input##{component_id}-metadatum-#{@history.id}" \
      "[name='filters[metadata_type:#{@metadata_type.id}][metadatum_ids][]']" \
      "[value='#{@history.id}'][checked]"
    assert_equal(
      { "metadata_type:#{@metadata_type.id}" => { "metadatum_ids" => [ @history.id ] } },
      content_table_state.fetch("filters")
    )
  end

  test "legacy text metadata filters are removed while other saved state is preserved" do
    metadata_key = "metadata_type:#{@metadata_type.id}"
    ContentTablePreference.create!(
      user: @user,
      table_key: CONTENTS_TABLE_KEY,
      state: {
        "q" => "River",
        "filters" => {
          metadata_key => { "value" => "History" },
          "description" => { "value" => "Hydrology" }
        },
        "columns_present" => true,
        "columns" => [ "title", metadata_key ],
        "per_page" => 20,
        "sort_column" => "title",
        "sort_direction" => "asc",
        "page" => 1
      }
    )

    get contents_url

    assert_response :success
    state = content_table_state
    refute state.fetch("filters").key?(metadata_key)
    assert_equal({ "value" => "Hydrology" }, state.dig("filters", "description"))
    assert_equal "River", state.fetch("q")
    assert_equal 20, state.fetch("per_page")
    assert_equal [ "title", metadata_key ], state.fetch("columns")
    assert_equal [ "title", "asc" ], state.values_at("sort_column", "sort_direction")
  end

  test "clear filters preserves search per page and columns" do
    11.times do |index|
      create_content!(
        title: "River Extra #{index}",
        display_title: "Extra #{index}",
        description: "Hydrology field notes"
      )
    end
    cleared_filter_content = create_content!(
      title: "River Without Filter",
      display_title: "Cleared Filter Match",
      description: "Different field notes"
    )

    get table_contents_url, params: { per_page: 20 }
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "display_title" ]
    }
    get table_contents_url, params: {
      q: "River",
      filters: {
        "description" => { "value" => "Hydrology" }
      }
    }
    get table_contents_url, params: { clear_filters: "1" }

    assert_response :success
    assert_select "th", text: "Display title"
    assert_select "tbody tr", 13
    assert_includes @response.body, cleared_filter_content.display_title
    refute_includes @response.body, @other_content.display_title
  end

  test "index restores the saved table preference" do
    get table_contents_url, params: { per_page: 50 }
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "display_title" ]
    }
    get table_contents_url, params: {
      q: "River",
      filters: {
        "description" => { "value" => "Hydrology" }
      }
    }
    get table_contents_url, params: {
      sort_column: "display_title",
      sort_state: "default"
    }
    get contents_url

    assert_response :success
    assert_select "select[name='per_page'] option[value='50'][selected]"
    assert_select "input[name='q'][value='River']"
    assert_select "input[name='filters[description][value]'][value='Hydrology']"
    assert_sort_header "Display title", sort_key: "display_title", aria_sort: "ascending", current_direction: "asc"
    assert_includes @response.body, @matching_content.display_title
    refute_includes @response.body, @other_content.display_title

    assert_equal({
      "q" => "River",
      "filters" => { "description" => { "value" => "Hydrology" } },
      "columns" => [ "display_title" ],
      "per_page" => 50,
      "sort_column" => "display_title",
      "sort_direction" => "asc",
      "page" => 1
    }, content_table_state.slice("q", "filters", "columns", "per_page", "sort_column", "sort_direction", "page"))
  end

  test "table preferences survive authentication and remain isolated across browser sessions" do
    get table_contents_url, params: { q: "River", per_page: 50 }

    delete destroy_user_session_url
    post user_session_url, params: { user: { email: @user.email, password: "password" } }
    get contents_url

    assert_response :success
    assert_select "input[name='q'][value='River']"
    assert_select "select[name='per_page'] option[value='50'][selected]"

    same_user_browser = signed_in_browser(@user)
    same_user_browser.get contents_url
    same_user_page = Rails::Dom::Testing.html_document.parse(same_user_browser.response.body)

    assert_equal "River", same_user_page.at_css("input[name='q']")["value"]
    assert same_user_page.at_css("select[name='per_page'] option[value='50'][selected]")
    refute_includes same_user_browser.response.body, @other_content.title

    other_user = User.create!(
      name: "Other Table User",
      email: "other-table-user@example.com",
      password: "password",
      role: :volunteer
    )
    other_user_browser = signed_in_browser(other_user)
    other_user_browser.get contents_url
    other_user_page = Rails::Dom::Testing.html_document.parse(other_user_browser.response.body)

    assert_equal "", other_user_page.at_css("input[name='q']")["value"]
    assert other_user_page.at_css("select[name='per_page'] option[value='10'][selected]")
    assert_includes other_user_browser.response.body, @other_content.title
    assert_nil ContentTablePreference.find_by(user: other_user, table_key: CONTENTS_TABLE_KEY)
  end

  test "submitted table key cannot select another preference" do
    other_preference = ContentTablePreference.create!(
      user: @user,
      table_key: "shelves.123.contents",
      state: { "q" => "Mountain" }
    )

    get table_contents_url, params: {
      table_key: other_preference.table_key,
      q: "River"
    }

    assert_response :success
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title
    assert_equal "River", content_table_state.fetch("q")
    assert_equal({ "q" => "Mountain" }, other_preference.reload.state)
  end

  test "saved page is restored and clamped when records disappear" do
    create_paginated_contents!(18)

    get table_contents_url, params: { page: 2 }
    assert_equal 2, content_table_state.fetch("page")

    get contents_url

    assert_response :success
    assert_includes @response.body, @matching_content.title
    assert_equal 2, content_table_state.fetch("page")

    Content.where.not(id: @matching_content.id).destroy_all
    get contents_url

    assert_response :success
    assert_includes @response.body, @matching_content.title
    assert_equal 1, content_table_state.fetch("page")
  end

  test "query changes reset the saved page" do
    create_paginated_contents!(28, title_prefix: "River Extra", description: "Hydrology field notes")

    get table_contents_url, params: { page: 2 }
    assert_saved_page 2

    get table_contents_url, params: { q: "River" }
    assert_saved_page 1

    get table_contents_url, params: { page: 2 }
    get table_contents_url, params: { filters: { "description" => { "value" => "Hydrology" } } }
    assert_saved_page 1

    get table_contents_url, params: { page: 2 }
    get table_contents_url, params: { per_page: 20 }
    assert_saved_page 1

    get table_contents_url, params: { page: 2 }
    get table_contents_url, params: { sort_column: "title", sort_state: "default" }
    assert_saved_page 1
  end

  test "column changes retain page and clear sorting for a hidden column" do
    create_paginated_contents!(18)
    get table_contents_url, params: {
      columns_present: "1",
      columns: %w[title display_title]
    }
    get table_contents_url, params: { sort_column: "title", sort_state: "default" }
    get table_contents_url, params: { page: 2 }

    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "display_title" ]
    }

    assert_response :success
    assert_saved_page 2
    assert_nil content_table_state["sort_column"]
    assert_nil content_table_state["sort_direction"]
    assert_nil content_header("Title")
    assert_sort_header "Display title", sort_key: "display_title", aria_sort: "none", current_direction: "default"
  end

  test "reset deletes only the contents table preference" do
    ContentTablePreference.create!(
      user: @user,
      table_key: CONTENTS_TABLE_KEY,
      state: { "q" => "River" }
    )
    other_preference = ContentTablePreference.create!(
      user: @user,
      table_key: "shelves.123.contents",
      state: { "q" => "Mountain" }
    )

    delete reset_table_contents_url, params: { table_key: other_preference.table_key }

    assert_response :see_other
    assert_redirected_to contents_url
    assert_nil ContentTablePreference.find_by(user: @user, table_key: CONTENTS_TABLE_KEY)
    assert_equal({ "q" => "Mountain" }, other_preference.reload.state)

    follow_redirect!
    assert_select "input[name='q'][value='']"
  end

  test "index deletes legacy session state without migrating it" do
    legacy_session = {
      "contents_index_state" => {
        "q" => "Mountain",
        "per_page" => 50
      }
    }

    get contents_url, env: {
      "action_dispatch.request.unsigned_session_cookie" => legacy_session
    }

    assert_response :success
    assert_nil request.session["contents_index_state"]
    assert_nil ContentTablePreference.find_by(user: @user, table_key: CONTENTS_TABLE_KEY)
    assert_select "input[name='q'][value='']"
  end

  test "pagination URLs contain only the page after table mutations" do
    create_paginated_contents!(18, title_prefix: "River Extra", description: "Hydrology field notes")

    get table_contents_url, params: {
      q: "River",
      filters: { "description" => { "value" => "Hydrology" } },
      sort_column: "title",
      sort_state: "default"
    }

    assert_response :success
    assert_select "turbo-frame#contents_table[data-turbo-prefetch='false']"
    pagination_links = css_select("nav.pagy-bootstrap a.page-link[href]")
    assert_predicate pagination_links, :any?
    pagination_links.each do |link|
      query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query.to_s)
      assert_equal [ "page" ], query.keys
    end
  end

  test "invalid state params are ignored" do
    11.times do |index|
      create_content!(
        title: "Extra #{index}",
        display_title: "Extra #{index}",
        description: "Other field notes"
      )
    end

    get table_contents_url, params: {
      per_page: 999,
      filters: {
        "not_a_column" => { "value" => "Nope" }
      }
    }

    assert_response :success
    assert_select "tbody tr", 10
    assert_select "th", text: "not_a_column", count: 0
  end

  test "invalid columns are ignored" do
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "not_a_column" ]
    }

    assert_response :success
    assert_select "th", text: "not_a_column", count: 0
    assert_select "td", text: "No columns selected."
  end

  test "pagination links target table action" do
    11.times do |index|
      create_content!(
        title: "Extra #{index}",
        display_title: "Extra #{index}",
        description: "Other field notes"
      )
    end

    get contents_url

    assert_response :success
    assert_select "turbo-frame#contents_table nav.pagy-bootstrap.series-nav ul.pagination" do
      assert_select "li.page-item a.page-link[href='#{table_contents_path}?page=2']"
    end
  end

  test "every visible content and metadata header is a direct Turbo sort link" do
    language_type = MetadataType.create!(
      name: "Language",
      order: 2,
      user: @user
    )
    expected_headers = [
      [ "ID", "id" ],
      [ "Title", "title" ],
      [ "Display title", "display_title" ],
      [ "Description", "description" ],
      [ "Year of publication", "year_of_publication" ],
      [ "Additional notes", "additional_notes" ],
      [ "Date created", "created_at" ],
      [ "Date updated", "updated_at" ],
      [ "Added by", "added_by" ],
      [ "Subject", "metadata_type:#{@metadata_type.id}" ],
      [ "Language", "metadata_type:#{language_type.id}" ]
    ]

    get table_contents_url, params: {
      columns_present: "1",
      columns: expected_headers.map(&:last)
    }

    assert_response :success
    assert_select "thead th", count: expected_headers.size + 2
    expected_headers.each do |label, sort_key|
      assert_sort_header label,
        sort_key: sort_key,
        aria_sort: "none",
        current_direction: "default"
    end
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
  end

  test "sort header sends current state and server advances through all three states" do
    zulu_content = create_content!(
      title: "Zulu File",
      display_title: "Zulu Display",
      description: "Zulu notes"
    )
    @matching_content.update_column(:created_at, Time.zone.local(2026, 1, 3))
    zulu_content.update_column(:created_at, Time.zone.local(2026, 1, 2))
    @other_content.update_column(:created_at, Time.zone.local(2026, 1, 1))

    get contents_url

    assert_equal [ "River Archive", "Zulu File", "Mountain File" ], content_column_values("Title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"

    click_content_header "Title"

    assert_equal [ "Mountain File", "River Archive", "Zulu File" ], content_column_values("Title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 1

    click_content_header "Title"

    assert_equal [ "Zulu File", "River Archive", "Mountain File" ], content_column_values("Title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "descending", current_direction: "desc"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 1

    click_content_header "Title"

    assert_equal [ "River Archive", "Zulu File", "Mountain File" ], content_column_values("Title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
  end

  test "sorting another column replaces the active sort" do
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "title", "display_title" ]
    }

    click_content_header "Title"

    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"
    assert_sort_header "Display title", sort_key: "display_title", aria_sort: "none", current_direction: "default"

    click_content_header "Display title"

    assert_equal [ "Display Match", "Display Miss" ], content_column_values("Display title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_sort_header "Display title", sort_key: "display_title", aria_sort: "ascending", current_direction: "asc"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 1
  end

  test "all fixed database columns apply ascending descending and null-last ordering" do
    third_content = create_content!(
      title: "Third File",
      display_title: "Third Display",
      description: "Temporary notes"
    )
    first_time = Time.zone.local(2026, 1, 1)
    second_time = Time.zone.local(2026, 1, 2)
    third_time = Time.zone.local(2026, 1, 3)
    @matching_content.update_columns(
      description: "Bravo",
      year_of_publication: 2025,
      additional_notes: 2,
      created_at: second_time,
      updated_at: second_time
    )
    @other_content.update_columns(
      description: nil,
      year_of_publication: nil,
      additional_notes: nil,
      created_at: first_time,
      updated_at: third_time
    )
    third_content.update_columns(
      description: "alpha",
      year_of_publication: 2024,
      additional_notes: 1,
      created_at: third_time,
      updated_at: first_time
    )

    cases = [
      [ "ID", "id",
        [ @matching_content.title, @other_content.title, third_content.title ],
        [ third_content.title, @other_content.title, @matching_content.title ] ],
      [ "Description", "description",
        [ third_content.title, @matching_content.title, @other_content.title ],
        [ @matching_content.title, third_content.title, @other_content.title ] ],
      [ "Year of publication", "year_of_publication",
        [ third_content.title, @matching_content.title, @other_content.title ],
        [ @matching_content.title, third_content.title, @other_content.title ] ],
      [ "Additional notes", "additional_notes",
        [ third_content.title, @matching_content.title, @other_content.title ],
        [ @matching_content.title, third_content.title, @other_content.title ] ],
      [ "Date created", "created_at",
        [ @other_content.title, @matching_content.title, third_content.title ],
        [ third_content.title, @matching_content.title, @other_content.title ] ],
      [ "Date updated", "updated_at",
        [ third_content.title, @matching_content.title, @other_content.title ],
        [ @other_content.title, @matching_content.title, third_content.title ] ]
    ]

    cases.each do |label, key, ascending_titles, descending_titles|
      get table_contents_url, params: {
        columns_present: "1",
        columns: [ "title", key ]
      }

      click_content_header label
      assert_equal ascending_titles, content_column_values("Title"), "#{label} ascending"

      click_content_header label
      assert_equal descending_titles, content_column_values("Title"), "#{label} descending"
    end
  end

  test "sort and search persist across direct header requests" do
    create_content!(
      title: "Zebra File",
      display_title: "Zebra Display",
      description: "Zebra notes"
    )

    get contents_url
    click_content_header "Title"
    get table_contents_url, params: { q: "File" }

    assert_equal [ "Mountain File", "Zebra File" ], content_column_values("Title")
    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"

    click_content_header "Title"

    assert_equal [ "Zebra File", "Mountain File" ], content_column_values("Title")
    refute_includes @response.body, @matching_content.title
    assert_sort_header "Title", sort_key: "title", aria_sort: "descending", current_direction: "desc"
  end

  test "sort persists across filters per page and pagination" do
    11.times do |index|
      create_content!(
        title: "Sorted Extra #{index.to_s.rjust(2, "0")}",
        display_title: "Extra #{index}",
        description: "Other notes"
      )
    end

    get contents_url
    click_content_header "Title"
    get table_contents_url, params: { per_page: 20 }
    get table_contents_url, params: {
      filters: { "description" => { "value" => "field notes" } }
    }

    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"
    assert_equal [ "Mountain File", "River Archive" ], content_column_values("Title")

    get table_contents_url, params: { clear_filters: "1" }
    get table_contents_url, params: { per_page: 10 }
    get table_contents_url, params: { page: 2 }

    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"
    assert_equal [ "Sorted Extra 08", "Sorted Extra 09", "Sorted Extra 10" ], content_column_values("Title")
  end

  test "stale malformed and partial sort requests preserve the active sort" do
    get contents_url
    click_content_header "Title"

    get table_contents_url, params: { sort_column: "title", sort_state: "default" }
    get table_contents_url, params: { sort_column: "title", sort_state: "sideways" }
    get table_contents_url, params: { sort_column: "title" }

    assert_sort_header "Title", sort_key: "title", aria_sort: "ascending", current_direction: "asc"
    assert_equal [ "Mountain File", "River Archive" ], content_column_values("Title")
  end

  test "hidden and invalid sort state is ignored and does not persist" do
    get contents_url
    click_content_header "Title"

    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "display_title" ]
    }

    assert_nil content_header("Title")
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0

    get table_contents_url, params: { sort_column: "title", sort_state: "default" }
    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "title", "display_title" ]
    }

    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0

    get table_contents_url, params: { sort_column: "not_a_column", sort_state: "default" }

    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0

    get table_contents_url, params: { sort_column: "title", sort_state: "sideways" }

    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
  end

  test "metadata sorting uses the lowest value per type and keeps missing values last" do
    language_type = MetadataType.create!(
      name: "Language",
      order: 2,
      user: @user
    )
    zoology = Metadatum.create!(
      name: "Zoology",
      metadata_type: @metadata_type,
      user: @user,
      under_review: false
    )
    arabic = Metadatum.create!(
      name: "Arabic",
      metadata_type: language_type,
      user: @user,
      under_review: false
    )
    english = Metadatum.create!(
      name: "English",
      metadata_type: language_type,
      user: @user,
      under_review: false
    )
    @matching_content.metadata << [ zoology, english ]
    @other_content.metadata << arabic
    untagged_content = create_content!(
      title: "Untagged File",
      display_title: "Untagged",
      description: "No metadata"
    )
    subject_key = "metadata_type:#{@metadata_type.id}"
    language_key = "metadata_type:#{language_type.id}"

    get table_contents_url, params: {
      columns_present: "1",
      columns: [ "title", subject_key, language_key ]
    }

    assert_sort_header "Subject", sort_key: subject_key, aria_sort: "none", current_direction: "default"
    assert_sort_header "Language", sort_key: language_key, aria_sort: "none", current_direction: "default"

    click_content_header "Subject"

    assert_equal [ @matching_content.title, @other_content.title, untagged_content.title ], content_column_values("Title")
    assert_equal "History, Zoology", content_column_values("Subject").first
    assert_includes @response.body, zoology.name
    assert_sort_header "Subject", sort_key: subject_key, aria_sort: "ascending", current_direction: "asc"

    click_content_header "Subject"

    assert_equal [ @other_content.title, @matching_content.title, untagged_content.title ], content_column_values("Title")
    assert_sort_header "Subject", sort_key: subject_key, aria_sort: "descending", current_direction: "desc"

    click_content_header "Language"

    assert_equal [ @other_content.title, @matching_content.title, untagged_content.title ], content_column_values("Title")
    assert_sort_header "Subject", sort_key: subject_key, aria_sort: "none", current_direction: "default"
    assert_sort_header "Language", sort_key: language_key, aria_sort: "ascending", current_direction: "asc"
    assert_select "tbody tr", count: 3
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 1

    get table_contents_url, params: {
      filters: { language_key => { "metadatum_ids" => [ english.id ] } }
    }

    assert_equal [ @matching_content.title ], content_column_values("Title")

    language_type.destroy!
    get table_contents_url

    assert_response :success
    assert_nil content_header("Language")
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
    refute_includes content_table_state.fetch("columns"), language_key
    refute content_table_state.fetch("filters").key?(language_key)
    assert_nil content_table_state["sort_column"]
    assert_nil content_table_state["sort_direction"]
  end

  test "added by sorts by the displayed user value" do
    alpha_user = User.create!(
      name: "Alpha Author",
      email: "alpha-author@example.com",
      password: "password",
      role: :volunteer
    )
    create_content!(
      title: "Alpha Author File",
      display_title: "Alpha Author Display",
      description: "Authored elsewhere",
      user: alpha_user
    )
    fallback_user = User.create!(
      name: "Temporary Author",
      email: "aardvark-author@example.com",
      password: "password",
      role: :volunteer
    )
    fallback_user.update_column(:name, "\t")
    create_content!(
      title: "Fallback Author File",
      display_title: "Fallback Author Display",
      description: "Authored with an email fallback",
      user: fallback_user
    )

    get contents_url
    click_content_header "Added by"

    assert_equal fallback_user.email, content_column_values("Added by").first
    assert_sort_header "Added by", sort_key: "added_by", aria_sort: "ascending", current_direction: "asc"

    click_content_header "Added by"

    assert_equal fallback_user.email, content_column_values("Added by").last
    assert_sort_header "Added by", sort_key: "added_by", aria_sort: "descending", current_direction: "desc"
  end

  private

  def content_header(label)
    css_select("thead th").find { |header| header.text.squish.start_with?(label) }
  end

  def content_sort_link(label)
    header = content_header(label)
    assert header, "Expected a visible #{label.inspect} content table header"

    link = header.at_css("a")
    assert link, "Expected #{label.inspect} header to contain a sort link"
    link
  end

  def sort_link_params(label)
    uri = URI.parse(content_sort_link(label)["href"])
    Rack::Utils.parse_nested_query(uri.query.to_s)
  end

  def assert_sort_header(label, sort_key:, aria_sort:, current_direction:)
    header = content_header(label)
    assert header, "Expected a visible #{label.inspect} content table header"
    assert_equal aria_sort, header["aria-sort"]

    link = content_sort_link(label)
    uri = URI.parse(link["href"])
    assert_equal table_contents_path, uri.path
    assert_equal "contents_table", link["data-turbo-frame"]
    assert_equal "false", link["data-turbo-prefetch"]
    assert_equal sort_key, sort_link_params(label)["sort_column"]
    assert_equal current_direction, sort_link_params(label)["sort_state"]
  end

  def click_content_header(label)
    get content_sort_link(label)["href"], headers: { "Turbo-Frame" => "contents_table" }

    assert_response :success
    assert_select "turbo-frame#contents_table", count: 1
  end

  def content_column_values(label)
    headers = css_select("thead th")
    column_index = headers.index { |header| header.text.squish.start_with?(label) }
    assert_not_nil column_index, "Expected a visible #{label.inspect} content table column"

    css_select("tbody tr").map do |row|
      row.css("td")[column_index].text.squish
    end
  end

  def content_table_state
    ContentTablePreference.find_by!(user: @user, table_key: CONTENTS_TABLE_KEY).state
  end

  def assert_saved_page(page)
    assert_equal page, content_table_state.fetch("page")
  end

  def create_paginated_contents!(count, title_prefix: "Page Extra", description: "Other field notes")
    count.times do |index|
      create_content!(
        title: "#{title_prefix} #{index}",
        display_title: "Page display #{index}",
        description:
      )
    end
  end

  def signed_in_browser(user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |browser|
      browser.post user_session_path, params: {
        user: { email: user.email, password: "password" }
      }
    end
  end

  def create_content!(
    title:,
    display_title:,
    description:,
    user: @user,
    filename: "#{title.parameterize}.pdf",
    content_type: "application/pdf",
    bytes: "file contents for #{title}"
  )
    content = user.contents.build(
      title: title,
      display_title: display_title,
      description: description,
      year_of_publication: 2026,
      additional_notes: 1
    )
    content.file.attach(
      io: StringIO.new(bytes),
      filename:,
      content_type:
    )
    content.save!
    content
  end
end
