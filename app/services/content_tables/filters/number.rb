module ContentTables
  module Filters
    class Number < Base
      DEFAULT_INPUT_PARTIAL = "content_tables/filters/number"

      def initialize(attribute: nil, input_partial: DEFAULT_INPUT_PARTIAL, apply: nil, &block)
        super(attribute:, input_partial:, permitted_fields: [ :value ], apply:, &block)
      end

      def normalize(raw_filter)
        value = raw_value(raw_filter, "value")
        integer = Integer(value, exception: false) if value.is_a?(String) || value.is_a?(Integer)

        integer.nil? ? {} : { "value" => integer }
      end

      private

      def apply_attribute(relation:, values:)
        relation.where(attribute.eq(values.fetch("value")))
      end
    end
  end
end
