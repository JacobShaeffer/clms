require "test_helper"

class ContentTables::ColumnTest < ActiveSupport::TestCase
  test "supports callable and partial cell renderers" do
    callable = ContentTables::Column.new(
      key: :title,
      label: "Title",
      group: :content,
      cell: ->(content) { content.title }
    )
    partial = ContentTables::Column.new(
      key: :actions,
      label: "Actions",
      group: :content,
      cell_partial: "custom/actions"
    )

    assert_equal contents(:one).title, callable.value(contents(:one))
    assert_equal "custom/actions", partial.cell_partial
    assert_raises(ArgumentError) { partial.value(contents(:one)) }
  end

  test "requires exactly one cell renderer" do
    assert_raises(ArgumentError) do
      ContentTables::Column.new(key: :missing, label: "Missing", group: :content)
    end
    assert_raises(ArgumentError) do
      ContentTables::Column.new(
        key: :both,
        label: "Both",
        group: :content,
        cell: ->(record) { record.id },
        cell_partial: "custom/cell"
      )
    end
  end

  test "columns without a sort adapter are not sortable" do
    column = ContentTables::Column.new(
      key: :plain,
      label: "Plain",
      group: :content,
      cell: ->(record) { record.id }
    )

    refute column.sortable?
    refute column.filterable?
  end

  test "a custom sort adapter receives its context and orders the relation" do
    calls = []
    adapter = Object.new
    adapter.define_singleton_method(:apply) do |relation:, direction:, column:|
      calls << { relation:, direction:, column: }
      relation.reorder(id: direction)
    end
    column = ContentTables::Column.new(
      key: :custom,
      label: "Custom",
      group: :content,
      cell: ->(record) { record.id },
      sort: adapter
    )
    relation = Content.where(id: [ contents(:one).id, contents(:two).id ])

    sorted = column.apply_sort(relation:, direction: :desc)

    assert_equal [ contents(:two).id, contents(:one).id ].sort.reverse, sorted.ids
    assert_equal [ { relation:, direction: :desc, column: } ], calls
  end
end
