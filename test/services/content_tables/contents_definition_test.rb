require "test_helper"

class ContentTables::ContentsDefinitionTest < ActiveSupport::TestCase
  StateDouble = Data.define(:q, :filters, :selected_column_keys, :sort_column, :sort_direction)

  setup do
    @first = contents(:one)
    @second = contents(:two)
    @first.update_columns(
      title: "River Archive",
      display_title: "First Display",
      description: "Hydrology notes",
      year_of_publication: 2025,
      additional_notes: 2,
      created_at: Time.zone.local(2026, 1, 2),
      updated_at: Time.zone.local(2026, 1, 3)
    )
    @second.update_columns(
      title: "Mountain File",
      display_title: "River Display",
      description: "Geology notes",
      year_of_publication: 2026,
      additional_notes: 1,
      created_at: Time.zone.local(2026, 1, 1),
      updated_at: Time.zone.local(2026, 1, 4)
    )
    users(:one).update_column(:name, "Zulu Author")
    users(:two).update_column(:name, "Alpha Author")
    metadata_types(:one).update_column(:name, "Subject")
    metadata_types(:two).update_column(:name, "Language")
    Metadatum.find_by!(metadata_type: metadata_types(:one)).update_column(:name, "History")
    Metadatum.find_by!(metadata_type: metadata_types(:two)).update_column(:name, "English")
    @metadata_types = MetadataType.order(:order, :name, :id).to_a
    @definition = build_definition
  end

  test "defines current content and dynamic metadata columns and defaults" do
    assert_equal ContentTables::ContentsDefinition::STATE_KEY, @definition.state_key
    assert_equal "contents_table", @definition.frame_id
    assert_equal "Search by title", @definition.search_placeholder
    assert @definition.selectable?
    assert_nil @definition.selection_form_id
    assert_equal %w[id title display_title description year_of_publication additional_notes created_at updated_at added_by],
      @definition.columns_for_group(:content).map(&:key)
    assert_equal @metadata_types.map { |type| "metadata_type:#{type.id}" },
      @definition.columns_for_group(:metadata).map(&:key)
    assert_equal %w[title created_at added_by] + @metadata_types.first(2).map { |type| "metadata_type:#{type.id}" },
      @definition.default_column_keys
    assert_equal [ :content, :metadata, :advanced ], @definition.filter_groups.map { |group| group.fetch(:key) }
    assert_equal %w[id title display_title year_of_publication added_by],
      @definition.columns_for_filter_group(:content).map(&:key)
    assert_equal %w[created_at updated_at description additional_notes],
      @definition.columns_for_filter_group(:advanced).map(&:key)
    assert_equal "No metadata types available.",
      @definition.groups.find { |group| group[:key] == :metadata }[:empty_message]
  end

  test "quick search remains title only and is case insensitive" do
    assert_equal [ @first.id ], relation_for(q: "River").ids
    assert_equal [ @first.id ], relation_for(q: "river").ids
  end

  test "built-in content filters apply text number date range and added-by values" do
    assert_equal [ @first.id ], relation_for(filters: { "description" => { "value" => "hydrology" } }).ids
    assert_equal [ @first.id ], relation_for(filters: { "year_of_publication" => { "value" => 2025 } }).ids
    assert_equal [ @first.id ], relation_for(filters: {
      "created_at" => { "from" => "2026-01-02", "to" => "2026-01-02" }
    }).ids
    assert_equal [ @second.id ], relation_for(filters: { "added_by" => { "value" => "alpha" } }).ids
  end

  test "metadata columns filter sort and render values" do
    subject_type = metadata_types(:one)
    alpha = Metadatum.create!(
      name: "Alpha",
      metadata_type: subject_type,
      user: users(:one),
      under_review: false
    )
    @second.metadata << alpha
    subject_key = "metadata_type:#{subject_type.id}"

    assert_equal [ @first.id ], relation_for(filters: { subject_key => { "value" => "history" } }).ids
    assert_equal [ @second.id, @first.id ], relation_for(
      selected_column_keys: [ subject_key ],
      sort_column: subject_key,
      sort_direction: "asc"
    ).ids
    assert_equal "History", @definition.column(subject_key).value(@first.reload)
  end

  test "fixed sorting retains case-insensitive null-last current behavior" do
    @first.update_column(:description, nil)

    assert_equal [ @second.id, @first.id ], relation_for(
      selected_column_keys: [ "description" ],
      sort_column: "description",
      sort_direction: "asc"
    ).ids
    assert_equal [ @second.id, @first.id ], relation_for(
      selected_column_keys: [ "description" ],
      sort_column: "description",
      sort_direction: "desc"
    ).ids
  end

  test "callers can replace and remove columns and replace complete rows" do
    replacement = ContentTables::Column.new(
      key: "title",
      label: "Custom title",
      group: :content,
      cell: ->(content) { content.title.upcase }
    )
    definition = build_definition(
      additional_columns: [ replacement ],
      excluded_column_keys: [ "description" ],
      row_partial: "custom/content_row"
    )

    assert_equal 1, definition.columns.count { |column| column.key == "title" }
    assert_nil definition.column("description")
    assert_equal "RIVER ARCHIVE", definition.column("title").value(@first)
    assert_equal "custom/content_row", definition.row_partial
  end

  test "derives its DOM prefix from a custom frame id" do
    definition = build_definition(frame_id: "shelf_42_contents_table")

    assert_equal "shelf-42-contents", definition.dom_prefix
    assert_equal "shelf-42-contents-advanced-filters", definition.dom_id("advanced-filters")
  end

  test "accepts a form id for selected content rows" do
    definition = build_definition(selection_form_id: "bulk-action-form")

    assert_equal "bulk-action-form", definition.selection_form_id
  end

  private

  def build_definition(**options)
    ContentTables::ContentsDefinition.new(
      source: Content.includes(:user, metadata: :metadata_type),
      metadata_types: @metadata_types,
      update_path: "/contents/table",
      reset_path: "/contents/reset_table",
      **options
    )
  end

  def relation_for(
    q: "",
    filters: {},
    selected_column_keys: @definition.default_column_keys,
    sort_column: nil,
    sort_direction: nil
  )
    state = StateDouble.new(q:, filters:, selected_column_keys:, sort_column:, sort_direction:)
    @definition.relation_for(state)
  end
end
