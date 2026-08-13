require "test_helper"

class ContentTables::TableTest < ActionView::TestCase
  class CustomFilterAdapter
    def permitted_fields
      %w[prefix]
    end

    def input_partial
      "content_tables_test/custom_filter"
    end

    def normalize(raw_filter)
      prefix = raw_filter["prefix"]
      prefix.is_a?(String) && prefix.strip.present? ? { "prefix" => prefix.strip } : {}
    end

    def apply(relation:, values:, **)
      prefix = ActiveRecord::Base.sanitize_sql_like(values.fetch("prefix"))
      relation.where(Content.arel_table[:title].matches("#{prefix}%", nil, true))
    end
  end

  class CustomSortAdapter
    def apply(relation:, direction:, **)
      relation.reorder(Content.arel_table[:title].public_send(direction))
    end
  end

  StateDouble = Data.define(
    :q,
    :filters,
    :selected_column_keys,
    :per_page,
    :sort_column,
    :sort_direction
  )
  PagyDouble = Data.define(:pages)

  setup do
    @controller.prepend_view_path Rails.root.join("test/fixtures/views")
    @record = contents(:one)
    @state = StateDouble.new(
      q: "",
      filters: {},
      selected_column_keys: [ "custom" ],
      per_page: 10,
      sort_column: nil,
      sort_direction: nil
    )
    @pagy = PagyDouble.new(pages: 1)
  end

  test "a custom cell partial replaces the default cell rendering" do
    column = ContentTables::Column.new(
      key: "custom",
      label: "Custom",
      group: :custom,
      cell_partial: "content_tables_test/custom_cell"
    )

    render_table(definition_for(column:))

    assert_select "tbody tr td .custom-cell", text: @record.title.upcase
  end

  test "a definition row partial replaces the complete generic row" do
    column = ContentTables::Column.new(
      key: "custom",
      label: "Custom",
      group: :custom,
      cell: ->(record) { record.title }
    )

    render_table(definition_for(column:, row_partial: "content_tables_test/custom_row"))

    assert_select "tbody tr.custom-row", count: 1, text: /#{Regexp.escape(@record.title)} from a custom row/
    assert_select "tbody tr[id]", count: 0
  end

  test "an unsortable custom column renders a plain header without a link" do
    column = ContentTables::Column.new(
      key: "custom",
      label: "Unsortable custom field",
      group: :custom,
      cell: ->(record) { record.title }
    )

    render_table(definition_for(column:))

    assert_select "thead th[aria-sort='none']", text: "Unsortable custom field" do
      assert_select "a", count: 0
    end
  end

  test "the full component namespaces form controls and renders default group labels" do
    column = ContentTables::Column.new(
      key: "custom",
      label: "Custom",
      group: :custom,
      cell: ->(record) { record.title }
    )
    definition = definition_for(column:)

    render partial: "content_tables/content_table", locals: {
      definition:,
      state: @state,
      records: [ @record ],
      pagy: @pagy
    }

    assert_select "label[for='custom-search']", text: "Search"
    assert_select "input#custom-search[name='q']"
    assert_select "label[for='custom-per-page']", text: "Rows to display"
    assert_select "select#custom-per-page[name='per_page']"
    assert_select "#q, #per_page", count: 0
    assert_select ".dropdown-menu h2", text: "Custom columns"
    assert_select ".offcanvas h3", text: "Custom filters"
  end

  test "a custom column controls filtering sorting input and cell rendering" do
    contents(:one).update_column(:title, "River Zulu")
    contents(:two).update_column(:title, "River Alpha")
    column = ContentTables::Column.new(
      key: "custom",
      label: "Custom",
      group: :custom,
      cell_partial: "content_tables_test/custom_cell",
      filter: CustomFilterAdapter.new,
      sort: CustomSortAdapter.new
    )
    definition = definition_for(column:)
    state = ContentTables::State.new(
      user: users(:one),
      definition:,
      params: {
        filters: { custom: { prefix: " River " } },
        sort_column: "custom",
        sort_state: "default"
      }
    ).apply_request!
    records = definition.relation_for(state).to_a

    render partial: "content_tables/content_table", locals: {
      definition:,
      state:,
      records:,
      pagy: @pagy
    }

    assert_equal({ "custom" => { "prefix" => "River" } }, state.filters)
    assert_equal [ contents(:two).id, contents(:one).id ], records.map(&:id)
    assert_select ".custom-filter input[name='filters[custom][prefix]'][value='River']"
    assert_select "thead th a", text: /Custom/
    assert_select "tbody .custom-cell", text: "RIVER ALPHA"
  end

  private

  def render_table(definition)
    render partial: "content_tables/table", locals: {
      definition:,
      state: @state,
      records: [ @record ],
      pagy: @pagy
    }
  end

  def definition_for(column:, row_partial: nil)
    ContentTables::Definition.new(
      state_key: "test.custom-table",
      frame_id: "custom_table",
      update_path: "/custom/table",
      reset_path: "/custom/table/reset",
      source: Content.all,
      columns: [ column ],
      groups: [ { key: :custom } ],
      default_column_keys: [ column.key ],
      page_size_options: [ 10 ],
      default_page_size: 10,
      empty_message: "Nothing found.",
      quick_search: ->(relation:, **) { relation },
      default_order: ->(relation:) { relation },
      row_partial:
    )
  end
end
