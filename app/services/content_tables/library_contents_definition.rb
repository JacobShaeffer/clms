module ContentTables
  class LibraryContentsDefinition < ContentsDefinition
    LIBRARY_GROUP = {
      key: :library,
      columns_label: "Library columns",
      filters_label: "Library Filters"
    }.freeze
    LIBRARY_FOLDERS_COLUMN_KEY = "library_folders"

    attr_reader :library, :library_version

    def self.all_content_state_key(library)
      "libraries.#{library.id}.all_contents"
    end

    def self.library_content_state_key(library)
      "libraries.#{library.id}.library_contents"
    end

    def self.shelf_content_state_key(library, shelf)
      "libraries.#{library.id}.shelves.#{shelf.id}.contents"
    end

    def initialize(
      library:,
      library_version: library.current_version,
      source:,
      metadata_types:,
      update_path:,
      reset_path:,
      state_key:,
      frame_id:,
      search_enabled: true,
      filters_enabled: true,
      path_index: nil,
      selection_form_id: nil
    )
      @library = library
      @library_version = library_version
      @path_index = path_index || LibraryFolderPathIndex.new(library:, library_version:)
      metadata_types = Array(metadata_types)
      library_column = build_library_folders_column

      super(
        source:,
        metadata_types:,
        update_path:,
        reset_path:,
        state_key:,
        frame_id:,
        additional_columns: [ library_column ],
        additional_groups: [ LIBRARY_GROUP ],
        default_column_keys: DEFAULT_CONTENT_COLUMN_KEYS +
          metadata_types.first(2).map { |metadata_type| "metadata_type:#{metadata_type.id}" } +
        [ library_column.key ],
        search_enabled:,
        filters_enabled:,
        selection_form_id:
      )
    end

    def library_folders_for(content)
      library_folders_by_content_id.fetch(content.id, [])
    end

    def breadcrumb_for(folder)
      path_index.breadcrumb(folder)
    end

    private

    attr_reader :path_index

    def library_folders_by_content_id
      @library_folders_by_content_id ||= library_version.library_folder_contents
        .includes(:library_folder)
        .group_by(&:content_id)
        .transform_values do |placements|
          placements
            .map(&:library_folder)
            .sort_by { |folder| [ folder.name.downcase, folder.name, folder.id ] }
        end
    end

    def build_library_folders_column
      filter = Filters::Text.new(apply: lambda do |relation:, values:, **|
        query = ActiveRecord::Base.sanitize_sql_like(values.fetch("value"))
        matching_content_ids = LibraryFolderContent
          .where(library_version_id: library_version.id)
          .joins(:library_folder)
          .where(LibraryFolder.arel_table[:name].matches("%#{query}%"))
          .select(:content_id)

        relation.where(id: matching_content_ids)
      end)

      Column.new(
        key: LIBRARY_FOLDERS_COLUMN_KEY,
        label: "Library folders",
        group: :library,
        cell_partial: "content_tables/library_folders_cell",
        filter:,
        sort: Sorts::Expression.new(
          expression: library_folder_sort_expression,
          tie_breaker: Content.arel_table[:id]
        )
      )
    end

    def library_folder_sort_expression
      contents = Content.arel_table
      placements = LibraryFolderContent.arel_table
      folders = LibraryFolder.arel_table
      minimum_name = Arel::Nodes::NamedFunction.new("MIN", [ folders[:name].lower ])
      subquery = placements
        .project(minimum_name)
        .join(folders)
        .on(folders[:id].eq(placements[:library_folder_id]))
        .where(placements[:content_id].eq(contents[:id]))
        .where(placements[:library_version_id].eq(library_version.id))

      Arel::Nodes::Grouping.new(subquery.ast)
    end
  end
end
