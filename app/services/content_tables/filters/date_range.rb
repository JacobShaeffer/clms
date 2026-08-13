module ContentTables
  module Filters
    class DateRange < Base
      DEFAULT_INPUT_PARTIAL = "content_tables/filters/date_range"

      def initialize(attribute: nil, input_partial: DEFAULT_INPUT_PARTIAL, apply: nil, &block)
        super(attribute:, input_partial:, permitted_fields: %i[ from to ], apply:, &block)
      end

      def normalize(raw_filter)
        %w[from to].each_with_object({}) do |field, normalized|
          date = parse_date(raw_value(raw_filter, field))
          normalized[field] = date.iso8601 if date
        end
      end

      private

      def apply_attribute(relation:, values:)
        from_date = parse_date(values["from"])
        to_date = parse_date(values["to"])
        relation = relation.where(attribute.gteq(from_date.beginning_of_day)) if from_date
        relation = relation.where(attribute.lteq(to_date.end_of_day)) if to_date
        relation
      end

      def parse_date(value)
        return if value.blank?

        Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
