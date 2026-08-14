module ContentTables
  module Sorts
    class Expression
      DIRECTIONS = {
        "asc" => :asc,
        "desc" => :desc
      }.freeze

      def initialize(expression:, tie_breaker: nil, prepare: nil)
        @expression = expression
        @tie_breaker = tie_breaker
        @prepare = prepare

        raise ArgumentError, "expression is required" if expression.nil?
        raise ArgumentError, "prepare must be callable" if prepare.present? && !prepare.respond_to?(:call)

        validate_expression!(expression, :expression) unless expression.respond_to?(:call)
        validate_expression!(tie_breaker, :tie_breaker) if tie_breaker.present? && !tie_breaker.respond_to?(:call)
      end

      def apply(relation:, direction:, column:)
        ordering_method = DIRECTIONS[direction.to_s]
        return relation unless ordering_method

        scope = prepare ? prepare.call(relation:, column:) : relation
        primary_expression = resolve(expression, column:)
        clauses = [ primary_expression.public_send(ordering_method).nulls_last ]

        if tie_breaker.present?
          resolved_tie_breaker = resolve(tie_breaker, column:)
          clauses << resolved_tie_breaker.public_send(ordering_method)
        end

        scope.reorder(*clauses)
      end

      private

      attr_reader :expression, :tie_breaker, :prepare

      def resolve(configured_expression, column:)
        resolved_expression = if configured_expression.respond_to?(:call)
          configured_expression.call(column:)
        else
          configured_expression
        end

        validate_expression!(resolved_expression, :resolved_expression)
        resolved_expression
      end

      def validate_expression!(value, name)
        valid = value.is_a?(Arel::Attributes::Attribute) || value.is_a?(Arel::Nodes::NodeExpression)
        unsafe_literal = value.is_a?(Arel::Nodes::SqlLiteral) || value.is_a?(Arel::Nodes::BoundSqlLiteral)
        return if valid && !unsafe_literal

        raise ArgumentError, "#{name} must be a composed Arel expression"
      end
    end
  end
end
