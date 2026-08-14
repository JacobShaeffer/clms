module ContentTables
  module Filters
    class Base
      attr_reader :input_partial, :permitted_fields

      def initialize(attribute:, input_partial:, permitted_fields:, apply: nil, &block)
        @attribute = attribute
        @input_partial = input_partial.to_s
        @permitted_fields = permitted_fields.map(&:to_s).freeze
        @applier = apply || block

        raise ArgumentError, "input_partial is required" if @input_partial.blank?
        raise ArgumentError, "attribute or apply callable is required" if @attribute.blank? && @applier.blank?
        raise ArgumentError, "apply must be callable" if @applier.present? && !@applier.respond_to?(:call)
      end

      def apply(relation:, values:, column:)
        return relation if values.blank?

        if applier
          applier.call(relation:, values:, column:)
        else
          apply_attribute(relation:, values:)
        end
      end

      private

      attr_reader :attribute, :applier

      def raw_value(raw_filter, field)
        return unless raw_filter.respond_to?(:[])

        raw_filter[field] || raw_filter[field.to_sym]
      end

      def apply_attribute(relation:, values:)
        raise NotImplementedError
      end
    end
  end
end
