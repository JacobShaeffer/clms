require "test_helper"

class ContentTables::DefinitionTest < ActiveSupport::TestCase
  StateDouble = Data.define(:q, :filters, :selected_column_keys, :sort_column, :sort_direction)

  setup do
    contents(:one).update_columns(title: "Zulu River", description: "Matching notes")
    contents(:two).update_columns(title: "Alpha Mountain", description: "Other notes")
    @title_column = ContentTables::Column.new(
      key: :title,
      label: "Title",
      group: :content,
      cell: ->(content) { content.title },
      filter: ContentTables::Filters::Text.new(attribute: Content.arel_table[:title]),
      sort: ContentTables::Sorts::Expression.new(
        expression: Content.arel_table[:title].lower,
        tie_breaker: Content.arel_table[:id]
      )
    )
    @plain_column = ContentTables::Column.new(
      key: :description,
      label: "Description",
      group: :content,
      cell: ->(content) { content.description },
      filter: ContentTables::Filters::Text.new(attribute: Content.arel_table[:description])
    )
    @definition = build_definition
  end

  test "applies quick search hidden filters and a selected sort" do
    state = StateDouble.new(
      q: "",
      filters: { "description" => { "value" => "notes" } },
      selected_column_keys: [ "title" ],
      sort_column: "title",
      sort_direction: "asc"
    )

    assert_equal [ contents(:two).id, contents(:one).id ], @definition.relation_for(state).ids
  end

  test "uses default order when a sort is unselected or unsupported" do
    contents(:one).update_column(:created_at, 1.day.ago)
    contents(:two).update_column(:created_at, 2.days.ago)
    state = StateDouble.new(
      q: "",
      filters: {},
      selected_column_keys: [ "description" ],
      sort_column: "title",
      sort_direction: "asc"
    )

    assert_equal [ contents(:one).id, contents(:two).id ], @definition.relation_for(state).ids
  end

  test "supports configurable groups DOM ids row partial and safe update URLs" do
    assert_equal [ @title_column, @plain_column ], @definition.columns_for_group(:content)
    assert_equal "Fields", @definition.groups.first.fetch(:columns_label)
    assert_equal "Content filters", @definition.groups.first.fetch(:filters_label)
    assert_equal "archive-advanced-filters", @definition.dom_id(:advanced_filters)
    assert_equal "custom/row", @definition.row_partial
    assert_equal "/archive/table", @definition.update_url
    assert_equal "/archive/table?q=river+%26+lake", @definition.update_url(q: "river & lake")

    definition_with_query = build_definition(update_path: "/archive/table?scope=all")
    assert_equal "/archive/table?scope=all&page=2", definition_with_query.update_url(page: 2)
  end

  test "supplies labels for groups that omit them" do
    definition = build_definition(groups: [ { key: :content } ])
    group = definition.groups.first

    assert_equal "Content columns", group.fetch(:columns_label)
    assert_equal "Content filters", group.fetch(:filters_label)
  end

  private

  def build_definition(
    update_path: "/archive/table",
    groups: [ { key: :content, columns_label: "Fields", custom: "kept" } ]
  )
    ContentTables::Definition.new(
      state_key: "archive.index",
      frame_id: "archive_table",
      update_path:,
      reset_path: "/archive/reset",
      source: -> { Content.all },
      columns: [ @title_column, @plain_column ],
      groups:,
      default_column_keys: [ :title ],
      page_size_options: [ 10, 25 ],
      default_page_size: 10,
      empty_message: "Nothing found.",
      quick_search: lambda do |relation:, query:|
        relation.where(Content.arel_table[:title].matches("%#{query}%"))
      end,
      default_order: ->(relation:) { relation.reorder(created_at: :desc, id: :desc) },
      row_partial: "custom/row",
      dom_prefix: "archive"
    )
  end
end
