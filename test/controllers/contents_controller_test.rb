require "test_helper"
require "stringio"

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
    assert_select "turbo-frame#contents_table"
    assert_select "turbo-frame#contents_table input[name='q']", count: 0
    assert_select "button", text: "Advanced Filters"
    assert_select ".offcanvas.offcanvas-end#contents-advanced-filters"
    assert_select "#contents-advanced-filters-title", text: "Advanced Filters"
    assert_select "input[name='filters[title][value]']"
    assert_select "input[name='filters[metadata_type:#{@metadata_type.id}][value]']"
    assert_select "form[action='#{table_contents_path}'] select[name='per_page']"
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
    get contents_url

    assert_response :success
    assert_select "select[name='per_page'] option[value='10'][selected]"
    assert_select "th", text: "Display title", count: 0
    assert_select "input[name='q'][value='']"
    assert_select "input[name='filters[description][value]'][value='']"
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
    assert_select "turbo-frame#contents_table a[href='#{table_contents_path}?page=2']"
  end

  private

  def create_content!(title:, display_title:, description:)
    content = @user.contents.build(
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
