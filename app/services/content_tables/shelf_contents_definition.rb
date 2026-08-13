module ContentTables
  class ShelfContentsDefinition < ContentsDefinition
    SHELF_GROUP = {
      key: :shelf,
      columns_label: "Shelf columns",
      filters_label: "Shelf Filters"
    }.freeze

    attr_reader :shelf

    def self.state_key_for(shelf)
      "shelves.#{shelf.id}.contents"
    end

    def initialize(
      user:,
      shelf:,
      source:,
      metadata_types:,
      update_path:,
      reset_path:
    )
      @user = user
      @shelf = shelf
      shelf_column = build_shelf_column
      metadata_types = Array(metadata_types)

      super(
        source:,
        metadata_types:,
        update_path:,
        reset_path:,
        frame_id: "shelf_#{shelf.id}_contents_table",
        state_key: self.class.state_key_for(shelf),
        additional_columns: [ shelf_column ],
        additional_groups: [ SHELF_GROUP ],
        default_column_keys: DEFAULT_CONTENT_COLUMN_KEYS +
          metadata_types.first(2).map { |metadata_type| "metadata_type:#{metadata_type.id}" } +
          [ shelf_column.key ]
      )
    end

    private

    attr_reader :user

    def build_shelf_column
      filter = Filters::Text.new(apply: lambda do |relation:, values:, **|
        query = ActiveRecord::Base.sanitize_sql_like(values.fetch("value"))
        matching_content_ids = ShelfContent.joins(:shelf)
          .where(shelves: { user_id: user.id })
          .where(Shelf.arel_table[:name].matches("%#{query}%"))
          .select(:content_id)

        relation.where(id: matching_content_ids)
      end)

      Column.new(
        key: "shelves",
        label: "Shelves",
        group: :shelf,
        cell: lambda do |content|
          content.shelves
            .select { |content_shelf| content_shelf.user_id == user.id }
            .sort_by { |content_shelf| [ content_shelf.name.downcase, content_shelf.name, content_shelf.id ] }
            .map(&:name)
            .join(", ")
        end,
        filter:,
        sort: Sorts::Expression.new(
          expression: shelf_sort_expression,
          tie_breaker: Content.arel_table[:id]
        )
      )
    end

    def shelf_sort_expression
      contents = Content.arel_table
      shelf_contents = ShelfContent.arel_table
      shelves = Shelf.arel_table
      minimum_name = Arel::Nodes::NamedFunction.new("MIN", [ shelves[:name].lower ])
      subquery = shelf_contents
        .project(minimum_name)
        .join(shelves)
        .on(shelves[:id].eq(shelf_contents[:shelf_id]))
        .where(shelf_contents[:content_id].eq(contents[:id]))
        .where(shelves[:user_id].eq(user.id))

      Arel::Nodes::Grouping.new(subquery.ast)
    end
  end
end
