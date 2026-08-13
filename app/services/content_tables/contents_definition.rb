module ContentTables
  class ContentsDefinition < Definition
    STATE_KEY = "contents.index"
    PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
    CONTENT_GROUP = {
      key: :content,
      columns_label: "Content columns",
      filters_label: "General Filters"
    }.freeze
    METADATA_GROUP = {
      key: :metadata,
      columns_label: "Metadata columns",
      filters_label: "Metadata Filters",
      empty_message: "No metadata types available."
    }.freeze
    DEFAULT_CONTENT_COLUMN_KEYS = %w[title created_at added_by].freeze

    def initialize(
      source:,
      metadata_types:,
      update_path:,
      reset_path:,
      frame_id: "contents_table",
      state_key: STATE_KEY,
      row_partial: nil,
      additional_columns: [],
      excluded_column_keys: [],
      additional_groups: [],
      default_column_keys: nil,
      dom_prefix: nil
    )
      metadata_types = Array(metadata_types)
      replacement_keys = Array(additional_columns).map(&:key)
      removed_keys = Array(excluded_column_keys).map(&:to_s) | replacement_keys
      configured_columns = (content_columns + metadata_columns(metadata_types))
        .reject { |column| removed_keys.include?(column.key) }
        .concat(additional_columns)

      super(
        state_key:,
        frame_id:,
        update_path:,
        reset_path:,
        source:,
        columns: configured_columns,
        groups: [ CONTENT_GROUP, METADATA_GROUP ] + Array(additional_groups),
        default_column_keys: default_column_keys || build_default_column_keys(metadata_types),
        page_size_options: PER_PAGE_OPTIONS,
        default_page_size: 10,
        empty_message: "No content found.",
        search_placeholder: "Search by title",
        quick_search: method(:apply_quick_search),
        default_order: method(:apply_default_order),
        row_partial:,
        dom_prefix:
      )
    end

    private

    def content_columns
      contents = Content.arel_table

      [
        Column.new(
          key: "id",
          label: "ID",
          group: :content,
          cell: ->(content) { content.id },
          filter: Filters::Number.new(attribute: contents[:id]),
          sort: Sorts::Expression.new(expression: contents[:id])
        ),
        text_content_column("title", "Title"),
        text_content_column("display_title", "Display title"),
        text_content_column("description", "Description"),
        number_content_column("year_of_publication", "Year of publication"),
        number_content_column("additional_notes", "Additional notes"),
        date_content_column("created_at", "Date created"),
        date_content_column("updated_at", "Date updated"),
        added_by_column
      ]
    end

    def text_content_column(key, label)
      attribute = Content.arel_table[key]
      Column.new(
        key:,
        label:,
        group: :content,
        cell: ->(content) { content.public_send(key) },
        filter: Filters::Text.new(attribute:),
        sort: Sorts::Expression.new(
          expression: attribute.lower,
          tie_breaker: Content.arel_table[:id]
        )
      )
    end

    def number_content_column(key, label)
      attribute = Content.arel_table[key]
      Column.new(
        key:,
        label:,
        group: :content,
        cell: ->(content) { content.public_send(key) },
        filter: Filters::Number.new(attribute:),
        sort: Sorts::Expression.new(
          expression: attribute,
          tie_breaker: Content.arel_table[:id]
        )
      )
    end

    def date_content_column(key, label)
      attribute = Content.arel_table[key]
      Column.new(
        key:,
        label:,
        group: :content,
        cell: ->(content) { content.public_send(key)&.strftime("%Y-%m-%d") },
        filter: Filters::DateRange.new(attribute:),
        sort: Sorts::Expression.new(
          expression: attribute,
          tie_breaker: Content.arel_table[:id]
        )
      )
    end

    def added_by_column
      filter = Filters::Text.new(apply: lambda do |relation:, values:, **|
        query = ActiveRecord::Base.sanitize_sql_like(values.fetch("value"))
        relation.joins(:user).where(
          "users.name ILIKE :query OR users.email ILIKE :query",
          query: "%#{query}%"
        )
      end)
      users = User.arel_table
      blank_name = users[:name].eq(nil).or(users[:name].matches_regexp("^[[:space:]]*$"))
      displayed_user = Arel::Nodes::Case.new
        .when(blank_name)
        .then(users[:email])
        .else(users[:name])

      Column.new(
        key: "added_by",
        label: "Added by",
        group: :content,
        cell: ->(content) { content.user&.name.presence || content.user&.email },
        filter:,
        sort: Sorts::Expression.new(
          expression: Arel::Nodes::NamedFunction.new("LOWER", [ displayed_user ]),
          tie_breaker: Content.arel_table[:id],
          prepare: ->(relation:, **) { relation.joins(:user) }
        )
      )
    end

    def metadata_columns(metadata_types)
      metadata_types.map do |metadata_type|
        metadata_type_id = metadata_type.id
        key = metadata_column_key(metadata_type_id)
        filter = Filters::Text.new(apply: lambda do |relation:, values:, **|
          query = ActiveRecord::Base.sanitize_sql_like(values.fetch("value"))
          matching_content_ids = Content.joins(:metadata)
            .where(metadata: { metadata_type_id: })
            .where("metadata.name ILIKE ?", "%#{query}%")
            .select(:id)

          relation.where(id: matching_content_ids)
        end)
        sort_expression = metadata_sort_expression(metadata_type_id)

        Column.new(
          key:,
          label: metadata_type.name,
          group: :metadata,
          cell: lambda do |content|
            content.metadata
              .select { |metadatum| metadatum.metadata_type_id == metadata_type_id }
              .sort_by { |metadatum| [ metadatum.name.downcase, metadatum.name ] }
              .map(&:name)
              .join(", ")
          end,
          filter:,
          sort: Sorts::Expression.new(
            expression: sort_expression,
            tie_breaker: Content.arel_table[:id]
          )
        )
      end
    end

    def build_default_column_keys(metadata_types)
      DEFAULT_CONTENT_COLUMN_KEYS + metadata_types.first(2).map { |metadata_type| metadata_column_key(metadata_type.id) }
    end

    def metadata_column_key(metadata_type_id)
      "metadata_type:#{metadata_type_id}"
    end

    def metadata_sort_expression(metadata_type_id)
      contents = Content.arel_table
      contents_metadata = ContentMetadatum.arel_table
      metadata = Metadatum.arel_table
      minimum_name = Arel::Nodes::NamedFunction.new("MIN", [ metadata[:name].lower ])
      subquery = contents_metadata
        .project(minimum_name)
        .join(metadata)
        .on(metadata[:id].eq(contents_metadata[:metadata_id]))
        .where(contents_metadata[:content_id].eq(contents[:id]))
        .where(metadata[:metadata_type_id].eq(metadata_type_id))

      Arel::Nodes::Grouping.new(subquery.ast)
    end

    def apply_quick_search(relation:, query:)
      escaped_query = ActiveRecord::Base.sanitize_sql_like(query)
      relation.where(Content.arel_table[:title].matches("%#{escaped_query}%"))
    end

    def apply_default_order(relation:)
      relation.reorder(Content.arel_table[:created_at].desc, Content.arel_table[:id].desc)
    end
  end
end
