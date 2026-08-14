require "test_helper"

class ContentTables::LibraryContentsDefinitionTest < ActiveSupport::TestCase
  StateDouble = Data.define(:q, :filters, :selected_column_keys, :sort_column, :sort_direction)

  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @zulu_folder = create_folder!("Zulu Folder")
    @alpha_folder = create_folder!("Alpha Folder", parent_folder: @zulu_folder)
    LibraryFolderContent.create!(library_folder: @zulu_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @alpha_folder, content: contents(:two))
    @metadata_types = MetadataType.order(:order, :name).to_a
    @definition = ContentTables::LibraryContentsDefinition.new(
      library: @library,
      source: Content.includes(:user, :library_folders, metadata: :metadata_type),
      metadata_types: @metadata_types,
      update_path: "/libraries/#{@library.id}/all_contents_table",
      reset_path: "/libraries/#{@library.id}/reset_all_contents_table",
      state_key: ContentTables::LibraryContentsDefinition.all_content_state_key(@library),
      frame_id: "library_#{@library.id}_all_contents_table"
    )
  end

  test "defines library-specific identifiers and a default library folders column" do
    assert_equal "libraries.#{@library.id}.all_contents", @definition.state_key
    assert_equal "library_#{@library.id}_all_contents_table", @definition.frame_id
    assert_includes @definition.default_column_keys, "library_folders"
    assert_equal "Library columns", @definition.groups.find { |group| group[:key] == :library }[:columns_label]
    assert_equal "content_tables/library_folders_cell", @definition.column("library_folders").cell_partial
  end

  test "builds distinct state keys for every library page table" do
    shelf = shelves(:one)

    assert_equal "libraries.#{@library.id}.library_contents",
      ContentTables::LibraryContentsDefinition.library_content_state_key(@library)
    assert_equal "libraries.#{@library.id}.shelves.#{shelf.id}.contents",
      ContentTables::LibraryContentsDefinition.shelf_content_state_key(@library, shelf)
  end

  test "returns folders and full breadcrumbs for the current library" do
    assert_equal [ @zulu_folder ], @definition.library_folders_for(contents(:one))
    assert_equal "Health Library / Zulu Folder", @definition.breadcrumb_for(@zulu_folder)
    assert_equal "Health Library / Zulu Folder / Alpha Folder", @definition.breadcrumb_for(@alpha_folder)
  end

  test "library folder filtering and sorting are case insensitive" do
    assert_equal [ contents(:two).id ], relation_for(
      filters: { "library_folders" => { "value" => "alpha folder" } }
    ).ids
    assert_equal [ contents(:two).id, contents(:one).id ], relation_for(
      sort_column: "library_folders",
      sort_direction: "asc"
    ).ids
  end

  private

  def create_folder!(name, parent_folder: nil)
    @library.library_folders.create!(
      name:,
      parent_folder:,
      user: users(:one),
      logo: library_assets(:one)
    )
  end

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
