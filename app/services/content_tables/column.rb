module ContentTables
  class Column
    attr_reader :key, :label, :group, :cell_partial, :filter, :sort

    def initialize(key:, label:, group:, cell: nil, cell_partial: nil, filter: nil, sort: nil)
      @key = key.to_s
      @label = label.to_s
      @group = group.to_sym
      @cell = cell
      @cell_partial = cell_partial&.to_s
      @filter = filter
      @sort = sort

      validate!
    end

    def value(record)
      raise ArgumentError, "#{key} uses a cell partial" if cell_partial.present?

      cell.call(record)
    end

    def filterable?
      filter.present?
    end

    def sortable?
      sort.present?
    end

    def normalize_filter(raw_filter)
      return {} unless filterable?

      normalized = filter.normalize(raw_filter)
      normalized.is_a?(Hash) ? normalized.deep_stringify_keys : {}
    rescue ArgumentError, TypeError
      {}
    end

    def apply_filter(relation:, values:)
      return relation unless filterable?

      filter.apply(relation:, values:, column: self)
    end

    def apply_sort(relation:, direction:)
      return relation unless sortable?

      sort.apply(relation:, direction:, column: self)
    end

    private

    attr_reader :cell

    def validate!
      raise ArgumentError, "key is required" if key.blank?
      raise ArgumentError, "label is required" if label.blank?
      raise ArgumentError, "provide either cell or cell_partial" if cell.blank? == cell_partial.blank?
      raise ArgumentError, "cell must be callable" if cell.present? && !cell.respond_to?(:call)

      validate_adapter!(filter, :filter, %i[ permitted_fields input_partial normalize apply ]) if filterable?
      validate_adapter!(sort, :sort, [ :apply ]) if sortable?
    end

    def validate_adapter!(adapter, name, methods)
      missing_methods = methods.reject { |method| adapter.respond_to?(method) }
      return if missing_methods.empty?

      raise ArgumentError, "#{name} adapter must respond to #{missing_methods.join(', ')}"
    end
  end
end
