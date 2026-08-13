module ContentTables
  module Filters
    class Text < Base
      DEFAULT_INPUT_PARTIAL = "content_tables/filters/text"

      def initialize(attribute: nil, input_partial: DEFAULT_INPUT_PARTIAL, apply: nil, &block)
        super(attribute:, input_partial:, permitted_fields: [ :value ], apply:, &block)
      end

      def normalize(raw_filter)
        value = raw_value(raw_filter, "value")
        return {} unless value.is_a?(String)

        value = value.strip
        value.present? ? { "value" => value } : {}
      end

      private

      def apply_attribute(relation:, values:)
        value = ActiveRecord::Base.sanitize_sql_like(values.fetch("value"))

        relation.where(attribute.matches("%#{value}%"))
      end
    end
  end
end
