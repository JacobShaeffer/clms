require "test_helper"

class ContentTables::Sorts::ExpressionTest < ActiveSupport::TestCase
  test "orders with composed Arel expressions nulls last and a tie breaker" do
    contents = Content.arel_table
    adapter = ContentTables::Sorts::Expression.new(
      expression: contents[:title].lower,
      tie_breaker: contents[:id]
    )

    relation = adapter.apply(relation: Content.all, direction: "asc", column: nil)

    assert_includes relation.to_sql,
      'ORDER BY LOWER("contents"."title") ASC NULLS LAST, "contents"."id" ASC'
  end

  test "rejects raw SQL strings and literals" do
    assert_raises(ArgumentError) do
      ContentTables::Sorts::Expression.new(expression: "LOWER(contents.title)")
    end
    assert_raises(ArgumentError) do
      ContentTables::Sorts::Expression.new(expression: Arel.sql("LOWER(contents.title)"))
    end
    adapter = ContentTables::Sorts::Expression.new(expression: ->(**) { "contents.title" })

    assert_raises(ArgumentError) do
      adapter.apply(relation: Content.all, direction: "asc", column: nil)
    end
  end
end
