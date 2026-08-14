require "test_helper"

class ContentTables::StateTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.content_table_preferences.delete_all
    @definition = build_definition
  end

  test "preserves an explicit empty column selection" do
    state = ContentTables::State.new(
      user: @user,
      definition: @definition,
      params: { columns_present: "1", columns: [] }
    ).apply_request!

    assert state.columns_present?
    assert_empty state.selected_column_keys
    assert state.dirty?
    state.persist!

    restored = ContentTables::State.new(user: @user, definition: @definition, params: {}).apply_request!
    assert restored.columns_present?
    assert_empty restored.selected_column_keys
  end

  test "actual query changes reset page while identical values do not" do
    create_preference(
      default_state.merge(
        "q" => "River",
        "per_page" => 20,
        "filters" => { "title" => { "value" => "Archive" } },
        "page" => 4
      )
    )

    unchanged = ContentTables::State.new(
      user: @user,
      definition: @definition,
      params: {
        q: "River",
        per_page: "20",
        filters: { title: { value: "Archive" } },
        page: "5"
      }
    ).apply_request!
    assert_equal 5, unchanged.page

    changed = ContentTables::State.new(
      user: @user,
      definition: @definition,
      params: { q: "Mountain", page: "7" }
    ).apply_request!
    assert_equal 1, changed.page
  end

  test "column changes retain page but clear a hidden sort" do
    create_preference(
      default_state.merge(
        "columns_present" => true,
        "columns" => [ "title", "plain" ],
        "sort_column" => "title",
        "sort_direction" => "asc",
        "page" => 4
      )
    )

    state = ContentTables::State.new(
      user: @user,
      definition: @definition,
      params: { columns_present: "1", columns: [ "plain" ] }
    ).apply_request!

    assert_equal [ "plain" ], state.selected_column_keys
    assert_nil state.sort_column
    assert_nil state.sort_direction
    assert_equal 4, state.page
  end

  test "sorting follows the guarded default asc desc cycle and resets page" do
    create_preference(default_state.merge("page" => 4))

    ascending = build_state(sort_column: "title", sort_state: "default")
    assert_equal [ "title", "asc", 1 ], [ ascending.sort_column, ascending.sort_direction, ascending.page ]
    ascending.persist!

    stale = build_state(sort_column: "title", sort_state: "default")
    assert_equal [ "title", "asc" ], [ stale.sort_column, stale.sort_direction ]
    refute stale.dirty?

    descending = build_state(sort_column: "title", sort_state: "asc")
    assert_equal [ "title", "desc", 1 ], [ descending.sort_column, descending.sort_direction, descending.page ]
    descending.persist!

    cleared = build_state(sort_column: "title", sort_state: "desc")
    assert_nil cleared.sort_column
    assert_nil cleared.sort_direction
    assert_equal 1, cleared.page
  end

  test "applies sorting when the same request also changes query state" do
    create_preference(default_state.merge("page" => 4))

    state = build_state(
      q: "River",
      filters: { title: { value: "Archive" } },
      sort_column: "title",
      sort_state: "default"
    )

    assert_equal "River", state.q
    assert_equal({ "title" => { "value" => "Archive" } }, state.filters)
    assert_equal [ "title", "asc" ], [ state.sort_column, state.sort_direction ]
    assert_equal 1, state.page
  end

  test "rejects sorting by an unselected or unsortable column" do
    create_preference(
      default_state.merge("columns_present" => true, "columns" => [ "plain" ], "page" => 3)
    )

    unselected = build_state(sort_column: "title", sort_state: "default")
    assert_nil unselected.sort_column
    assert_equal 3, unselected.page

    unsortable = build_state(sort_column: "plain", sort_state: "default")
    assert_nil unsortable.sort_column
    assert_equal 3, unsortable.page
  end

  test "sanitizes malformed stored state against the current definition" do
    create_preference(
      {
        "q" => [ "not", "scalar" ],
        "filters" => {
          "title" => { "value" => "  River  ", "unpermitted" => "ignored" },
          "number" => { "value" => "not-a-number" },
          "removed" => { "value" => "ignored" }
        },
        "columns_present" => true,
        "columns" => [ "title", "removed", 123 ],
        "per_page" => 999,
        "sort_column" => "removed",
        "sort_direction" => "sideways",
        "page" => -2,
        "unknown" => "ignored"
      }
    )

    state = ContentTables::State.new(user: @user, definition: @definition, params: {}).apply_request!

    assert_equal "", state.q
    assert_equal({ "title" => { "value" => "River" } }, state.filters)
    assert_equal [ "title" ], state.selected_column_keys
    assert_equal 10, state.per_page
    assert_nil state.sort_column
    assert_equal 1, state.page
    assert state.dirty?

    state.persist!
    assert_equal state.to_h, @user.content_table_preferences.find_by!(table_key: "test.table").state
  end

  test "clear filters preserves all other state and resets page only when filters change" do
    create_preference(
      default_state.merge(
        "q" => "River",
        "filters" => { "title" => { "value" => "Archive" } },
        "per_page" => 20,
        "sort_column" => "title",
        "sort_direction" => "asc",
        "page" => 4
      )
    )

    state = build_state(clear_filters: "1")

    assert_empty state.filters
    assert_equal "River", state.q
    assert_equal 20, state.per_page
    assert_equal [ "title", "asc" ], [ state.sort_column, state.sort_direction ]
    assert_equal 1, state.page
  end

  test "accepts only a positive scalar page and persists clamping corrections" do
    create_preference(default_state.merge("page" => 8))

    malformed = build_state(page: [ "9" ])
    assert_equal 8, malformed.page

    state = build_state(page: "9")
    assert_equal 9, state.page
    state.clamp_page!(3).persist!

    assert_equal 3, ContentTablePreference.find_by!(user: @user, table_key: "test.table").state.fetch("page")
  end

  test "disabled search and filters remove saved values and ignore request values" do
    @definition = build_definition(search_enabled: false, filters_enabled: false)
    create_preference(
      default_state.merge(
        "q" => "Saved search",
        "filters" => { "title" => { "value" => "Saved filter" } }
      )
    )

    state = build_state(
      q: "Requested search",
      filters: { title: { value: "Requested filter" } }
    )

    assert_equal "", state.q
    assert_empty state.filters
    assert state.dirty?
    state.persist!
    assert_equal "", ContentTablePreference.find_by!(user: @user, table_key: "test.table").state.fetch("q")
    assert_empty ContentTablePreference.find_by!(user: @user, table_key: "test.table").state.fetch("filters")
  end

  private

  def build_state(params = {})
    ContentTables::State.new(user: @user, definition: @definition, params:).apply_request!
  end

  def create_preference(state)
    ContentTablePreference.create!(user: @user, table_key: @definition.state_key, state:)
  end

  def default_state
    {
      "q" => "",
      "filters" => {},
      "columns_present" => false,
      "columns" => [],
      "per_page" => 10,
      "sort_column" => nil,
      "sort_direction" => nil,
      "page" => 1
    }
  end

  def build_definition(**options)
    title = ContentTables::Column.new(
      key: "title",
      label: "Title",
      group: :content,
      cell: ->(record) { record.title },
      filter: ContentTables::Filters::Text.new(attribute: Content.arel_table[:title]),
      sort: ContentTables::Sorts::Expression.new(expression: Content.arel_table[:title].lower)
    )
    number = ContentTables::Column.new(
      key: "number",
      label: "Number",
      group: :content,
      cell: ->(record) { record.id },
      filter: ContentTables::Filters::Number.new(attribute: Content.arel_table[:id])
    )
    plain = ContentTables::Column.new(
      key: "plain",
      label: "Plain",
      group: :content,
      cell: ->(record) { record.description }
    )

    ContentTables::Definition.new(
      state_key: "test.table",
      frame_id: "test_table",
      update_path: "/test/table",
      reset_path: "/test/reset",
      source: Content.all,
      columns: [ title, number, plain ],
      groups: [ { key: :content } ],
      default_column_keys: [ "title", "plain" ],
      page_size_options: [ 10, 20 ],
      default_page_size: 10,
      empty_message: "None",
      quick_search: ->(relation:, **) { relation },
      default_order: ->(relation:) { relation },
      **options
    )
  end
end
