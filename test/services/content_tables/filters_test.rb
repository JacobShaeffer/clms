require "test_helper"

class ContentTables::FiltersTest < ActiveSupport::TestCase
  test "text normalizes and escapes wildcard characters" do
    contents(:one).update_column(:title, "100% Archive")
    contents(:two).update_column(:title, "100X Archive")
    filter = ContentTables::Filters::Text.new(attribute: Content.arel_table[:title])

    assert_equal({ "value" => "100%" }, filter.normalize("value" => " 100% "))
    assert_equal [ contents(:one).id ], filter.apply(
      relation: Content.all,
      values: { "value" => "100%" },
      column: nil
    ).ids
  end

  test "text drops malformed non-string values" do
    filter = ContentTables::Filters::Text.new(attribute: Content.arel_table[:title])

    assert_equal({}, filter.normalize("value" => [ "River" ]))
    assert_equal({}, filter.normalize("value" => { "nested" => "River" }))
  end

  test "text filtering is case insensitive" do
    contents(:one).update_column(:title, "River Archive")
    filter = ContentTables::Filters::Text.new(attribute: Content.arel_table[:title])

    assert_equal [ contents(:one).id ], filter.apply(
      relation: Content.all,
      values: { "value" => "river" },
      column: nil
    ).ids
  end

  test "number rejects non-integers and applies an exact match" do
    contents(:one).update_column(:year_of_publication, 2025)
    contents(:two).update_column(:year_of_publication, 2026)
    filter = ContentTables::Filters::Number.new(attribute: Content.arel_table[:year_of_publication])

    assert_equal({}, filter.normalize("value" => "2025x"))
    assert_equal({ "value" => 2025 }, filter.normalize("value" => " 2025 "))
    assert_equal [ contents(:one).id ], filter.apply(
      relation: Content.all,
      values: { "value" => 2025 },
      column: nil
    ).ids
  end

  test "date range keeps valid bounds and drops malformed bounds" do
    contents(:one).update_column(:created_at, Time.zone.local(2026, 1, 2, 12))
    contents(:two).update_column(:created_at, Time.zone.local(2026, 1, 4, 12))
    filter = ContentTables::Filters::DateRange.new(attribute: Content.arel_table[:created_at])

    values = filter.normalize("from" => "2026-01-01", "to" => "not-a-date")
    assert_equal({ "from" => "2026-01-01" }, values)
    assert_equal [ contents(:one).id ], filter.apply(
      relation: Content.all,
      values: { "from" => "2026-01-02", "to" => "2026-01-03" },
      column: nil
    ).ids
  end

  test "custom apply callable receives the relation values and column" do
    received = nil
    filter = ContentTables::Filters::Text.new(apply: lambda do |relation:, values:, column:|
      received = [ relation, values, column ]
      relation.where(id: contents(:two).id)
    end)
    column = ContentTables::Column.new(
      key: "custom",
      label: "Custom",
      group: :custom,
      cell: ->(content) { content.title },
      filter:
    )

    result = column.apply_filter(relation: Content.all, values: { "value" => "anything" })

    assert_equal [ contents(:two).id ], result.ids
    assert_equal({ "value" => "anything" }, received.second)
    assert_same column, received.third
  end
end
