module Contents
  class Sorter
    DIRECTIONS = {
      "asc" => "ASC",
      "desc" => "DESC"
    }.freeze

    CONTENT_EXPRESSIONS = {
      "id" => "contents.id",
      "title" => "LOWER(contents.title)",
      "display_title" => "LOWER(contents.display_title)",
      "description" => "LOWER(contents.description)",
      "year_of_publication" => "contents.year_of_publication",
      "additional_notes" => "contents.additional_notes",
      "created_at" => "contents.created_at",
      "updated_at" => "contents.updated_at"
    }.freeze

    ADDED_BY_EXPRESSION = <<~SQL.squish.freeze
      LOWER(
        CASE
          WHEN users.name IS NULL OR users.name ~ '^[[:space:]]*$' THEN users.email
          ELSE users.name
        END
      )
    SQL

    def self.call(relation:, column:, direction:)
      new(relation:, column:, direction:).call
    end

    def initialize(relation:, column:, direction:)
      @relation = relation
      @column = column
      @direction = DIRECTIONS[direction.to_s]
    end

    def call
      return default_order unless direction

      case column_type
      when "content"
        sort_content
      when "metadata"
        sort_metadata
      else
        default_order
      end
    end

    private

    attr_reader :relation, :column, :direction

    def sort_content
      key = column_value(:key).to_s

      if key == "added_by"
        ordered(relation.joins(:user), ADDED_BY_EXPRESSION)
      elsif (expression = CONTENT_EXPRESSIONS[key])
        ordered(relation, expression, tie_breaker: key != "id")
      else
        default_order
      end
    end

    def sort_metadata
      metadata_type_id = Integer(column_value(:metadata_type_id), exception: false)
      return default_order unless metadata_type_id&.positive?

      expression = ActiveRecord::Base.sanitize_sql_array(
        [ <<~SQL.squish, metadata_type_id ]
          (
            SELECT MIN(LOWER(metadata.name))
            FROM contents_metadata
            INNER JOIN metadata ON metadata.id = contents_metadata.metadata_id
            WHERE contents_metadata.content_id = contents.id
              AND metadata.metadata_type_id = ?
          )
        SQL
      )

      ordered(relation, expression)
    end

    def ordered(scope, expression, tie_breaker: true)
      clauses = [ "#{expression} #{direction} NULLS LAST" ]
      clauses << "contents.id #{direction}" if tie_breaker

      scope.reorder(Arel.sql(clauses.join(", ")))
    end

    def default_order
      relation.reorder(
        Content.arel_table[:created_at].desc,
        Content.arel_table[:id].desc
      )
    end

    def column_type
      column_value(:type).to_s
    end

    def column_value(key)
      return unless column.respond_to?(:[])

      column[key] || column[key.to_s]
    end
  end
end
