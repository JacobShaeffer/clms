require "test_helper"
require "stringio"
require "uri"

class ContentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  self.fixture_table_names = []

  setup do
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

  test "index renders table state controls" do
    get contents_url

    assert_response :success
    assert_select "h1", text: "Contents"
    assert_select "h1.title", count: 0
    assert_select "a.btn.btn-primary[data-turbo-frame='modal']", text: "New content"
    assert_select "turbo-frame#contents_table"
    assert_select "turbo-frame#contents_table input[name='q']", count: 0
    assert_select "form[action='#{table_contents_path}'][data-turbo-frame='contents_table'] input.form-control[name='q']"
    assert_select "button.btn.btn-secondary[data-bs-toggle='offcanvas'][data-bs-target='#contents-advanced-filters']", text: "Advanced Filters"
    assert_select ".offcanvas.offcanvas-end#contents-advanced-filters"
    assert_select "#contents-advanced-filters-title.offcanvas-title", text: "Advanced Filters"
    assert_select ".offcanvas-body input.form-control[name='filters[title][value]']"
    assert_select ".offcanvas-body input.form-control[name='filters[metadata_type:#{@metadata_type.id}][value]']"
    assert_select ".offcanvas-body input.btn.btn-primary[type='submit'][value='Apply Filters']"
    assert_select ".offcanvas-body button.btn.btn-secondary[name='clear_filters']", text: "Clear Filters"
    assert_select "turbo-frame#contents_table .table-responsive > table.table.table-striped.align-middle"
    assert_select "form[action='#{table_contents_path}'] select.form-select[name='per_page']"
  end

  test "new renders a Bootstrap content form" do
    get new_content_url

    assert_response :success
    assert_select "h1", text: "New content"
    assert_select "h1.title", count: 0
    assert_select "form[action='#{contents_path}'][method='post'][data-turbo-frame='_top']" do
      assert_select "label.form-label[for='content_title']", text: "Title"
      assert_select "input.form-control#content_title[name='content[title]']"
      assert_select "textarea.form-control#content_description[name='content[description]']"
      assert_select "input.btn.btn-primary[type='submit']"
      assert_select "a.btn.btn-secondary[href='#{contents_path}']", text: "Cancel"
    end
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
    assert_select "#metadatum_badge_#{@history.id}", text: @history.name
    assert_select "input#content_metadatum_ids_#{@history.id}[checked='checked'][value='#{@history.id}']"
    assert_select "#metadatum_badge_#{@science.id}", count: 0
  end

  test "metadata search returns matching values and marks selected values active" do
    get search_contents_url,
      params: {
        target: "metadataInput_#{@metadata_type.id}_list",
        metadata_type_id: @metadata_type.id,
        search: "Hist",
        selected_ids: @history.id.to_s,
        metadatum_count: 10
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='update'][target='metadataInput_#{@metadata_type.id}_list']"
    assert_select "button#selector_for\\=#{@history.id}.active", text: @history.name
    assert_select "button", text: @science.name, count: 0
    assert_select "button.list-group-item-success", text: /Add.*Hist/
  end

  test "authorized users can add and select a new metadatum" do
    assert_difference "Metadatum.count", 1 do
      post add_new_metadatum_contents_url,
        params: {
          target: "metadataBadge_#{@metadata_type.id}_container",
          metadata_type_id: @metadata_type.id,
          name: "  Geography  "
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    metadatum = Metadatum.find_by!(name: "Geography")
    assert metadatum.under_review?
    assert_select "turbo-stream[action='append'][target='metadataBadge_#{@metadata_type.id}_container']"
    assert_select "#metadatum_badge_#{metadatum.id}", text: metadatum.name
  end

  test "table action renders only the contents table frame" do
    get table_contents_url, params: { q: "River" }

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
        "description" => { "value" => "Hydrology" }
      }
    }
    get table_contents_url, params: { per_page: 20 }

    assert_response :success
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title
  end

  test "metadata filters persist in session" do
    get table_contents_url, params: {
      filters: {
        "metadata_type:#{@metadata_type.id}" => { "value" => "History" }
      }
    }
    get table_contents_url, params: { per_page: 20 }

    assert_response :success
    assert_includes @response.body, @matching_content.title
    refute_includes @response.body, @other_content.title
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

  test "index clears table session state" do
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
    assert_select "select[name='per_page'] option[value='10'][selected]"
    assert_select "th", text: "Display title", count: 0
    assert_select "input[name='q'][value='']"
    assert_select "input[name='filters[description][value]'][value='']"
    assert_sort_header "Title", sort_key: "title", aria_sort: "none", current_direction: "default"
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
    assert_includes @response.body, @matching_content.title
    assert_includes @response.body, @other_content.title
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
    assert_select "thead th", count: expected_headers.size
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

    language_type.destroy!
    get table_contents_url

    assert_response :success
    assert_nil content_header("Language")
    assert_select "th[aria-sort='ascending'], th[aria-sort='descending']", count: 0
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

  def create_content!(title:, display_title:, description:, user: @user)
    content = user.contents.build(
      title: title,
      display_title: display_title,
      description: description,
      year_of_publication: 2026,
      additional_notes: 1
    )
    content.file.attach(
      io: StringIO.new("file contents for #{title}"),
      filename: "#{title.parameterize}.png",
      content_type: "image/png"
    )
    content.save!
    content
  end
end
