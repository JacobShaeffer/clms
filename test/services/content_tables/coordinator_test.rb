require "test_helper"

class ContentTables::CoordinatorTest < ActiveSupport::TestCase
  Pagination = Data.define(:page, :last)

  setup do
    @user = users(:one)
    @user.content_table_preferences.delete_all
    @definition = build_definition
  end

  test "coordinates state relation pagination clamping and persistence" do
    ContentTablePreference.create!(
      user: @user,
      table_key: @definition.state_key,
      state: {
        "q" => "",
        "filters" => {},
        "columns_present" => false,
        "columns" => [],
        "per_page" => 10,
        "sort_column" => nil,
        "sort_direction" => nil,
        "page" => 8
      }
    )
    calls = []
    paginator = lambda do |relation:, page:, per_page:|
      calls << { relation:, page:, per_page: }
      [ Pagination.new(page, 2), relation.limit(per_page).to_a ]
    end

    table = ContentTables::Coordinator.call(
      user: @user,
      definition: @definition,
      params: {},
      paginator:
    )

    assert_equal [ 8, 2 ], calls.pluck(:page)
    assert_equal [ 10, 10 ], calls.pluck(:per_page)
    assert_equal 2, table.state.page
    assert_equal 2, table.pagy.page
    assert_equal Content.limit(10).to_a, table.records
    assert_equal 2, @user.content_table_preferences.find_by!(table_key: @definition.state_key).state.fetch("page")
  end

  private

  def build_definition
    column = ContentTables::Column.new(
      key: "title",
      label: "Title",
      group: :content,
      cell: ->(content) { content.title }
    )

    ContentTables::Definition.new(
      state_key: "test.coordinator",
      frame_id: "test_table",
      update_path: "/test/table",
      reset_path: "/test/reset",
      source: Content.all,
      columns: [ column ],
      groups: [ { key: :content } ],
      default_column_keys: [ "title" ],
      page_size_options: [ 10 ],
      default_page_size: 10,
      empty_message: "Nothing found.",
      quick_search: ->(relation:, **) { relation },
      default_order: ->(relation:) { relation }
    )
  end
end
