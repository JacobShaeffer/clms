require "test_helper"

class ContentTables::ShelfContentsDefinitionTest < ActiveSupport::TestCase
  StateDouble = Data.define(:q, :filters, :selected_column_keys, :sort_column, :sort_direction)

  setup do
    @user = users(:one)
    @shelf = shelves(:one)
    @shelf.update!(name: "Zulu Shelf")
    @second_shelf = @user.shelves.create!(name: "Alpha Shelf")
    @second_shelf.contents << contents(:two)
    @definition = ContentTables::ShelfContentsDefinition.new(
      user: @user,
      shelf: @shelf,
      source: Content.includes(:user, :shelves, metadata: :metadata_type),
      metadata_types: MetadataType.order(:order, :name),
      update_path: "/shelves/#{@shelf.id}/table",
      reset_path: "/shelves/#{@shelf.id}/reset_table"
    )
  end

  test "uses shelf-specific identifiers and selects the shelves column by default" do
    assert_equal "shelves.#{@shelf.id}.contents", @definition.state_key
    assert_equal "shelf_#{@shelf.id}_contents_table", @definition.frame_id
    assert_includes @definition.default_column_keys, "shelves"
    assert_equal "Shelf columns", @definition.groups.find { |group| group[:key] == :shelf }[:columns_label]
  end

  test "shelves column renders only the current user's shelves" do
    @second_shelf.contents << contents(:one)

    assert_equal "Alpha Shelf, Zulu Shelf", @definition.column("shelves").value(contents(:one).reload)
    assert_equal "Alpha Shelf", @definition.column("shelves").value(contents(:two).reload)
  end

  test "shelves filter is case insensitive and shelf names are sortable" do
    assert_equal [ contents(:two).id ], relation_for(
      filters: { "shelves" => { "value" => "alpha shelf" } }
    ).ids
    assert_equal [ contents(:two).id, contents(:one).id ], relation_for(
      sort_column: "shelves",
      sort_direction: "asc"
    ).ids
  end

  private

  def relation_for(filters: {}, sort_column: nil, sort_direction: nil)
    state = StateDouble.new(
      "",
      filters,
      @definition.default_column_keys,
      sort_column,
      sort_direction
    )
    @definition.relation_for(state)
  end
end
