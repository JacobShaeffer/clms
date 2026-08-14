module ContentTables
  class State
    SORT_DIRECTIONS = %w[asc desc].freeze
    SORT_STATES = %w[default asc desc].freeze
    SORT_CYCLE = {
      "default" => "asc",
      "asc" => "desc",
      "desc" => "default"
    }.freeze

    attr_reader :user, :definition

    def initialize(user:, definition:, params:)
      @user = user
      @definition = definition
      @params = params
      @preference = ContentTablePreference.find_by(user:, table_key: definition.state_key)
      @loaded_state = normalized_loaded_state(@preference&.state)
      @state = sanitize_state(@preference&.state)
      @dirty = @preference.present? && @state != @loaded_state
    end

    def apply_request!
      previous_state = @state.deep_dup
      query_changed = apply_query_request!
      apply_columns_request!
      sanitize_sort!(@state)
      sort_changed = apply_sort_request!
      query_changed ||= sort_changed

      if query_changed
        @state["page"] = 1
      elsif parameter_present?(:page) && (requested_page = positive_integer(parameter(:page)))
        @state["page"] = requested_page
      end

      @dirty ||= @state != previous_state
      self
    end

    def q
      @state.fetch("q")
    end

    def filters
      @state.fetch("filters")
    end

    def columns_present?
      @state.fetch("columns_present")
    end

    def selected_column_keys
      columns_present? ? @state.fetch("columns") : definition.default_column_keys
    end

    def per_page
      @state.fetch("per_page")
    end

    def sort_column
      @state["sort_column"]
    end

    def sort_direction
      @state["sort_direction"]
    end

    def page
      @state.fetch("page")
    end

    def clamp_page!(last_page)
      normalized_last_page = positive_integer(last_page) || 1
      return self if page <= normalized_last_page

      @state["page"] = normalized_last_page
      @dirty = true
      self
    end

    def persist!
      return self unless dirty?

      @preference = ContentTablePreference.save_state!(
        user:,
        table_key: definition.state_key,
        state: to_h
      )
      @loaded_state = to_h
      @dirty = false
      self
    end

    def dirty?
      @dirty
    end

    def to_h
      @state.deep_dup
    end

    private

    attr_reader :params

    def default_state
      {
        "q" => "",
        "filters" => {},
        "columns_present" => false,
        "columns" => [],
        "per_page" => definition.default_page_size,
        "sort_column" => nil,
        "sort_direction" => nil,
        "page" => 1
      }
    end

    def normalized_loaded_state(raw_state)
      raw_state.is_a?(Hash) ? raw_state.deep_stringify_keys : raw_state
    end

    def sanitize_state(raw_state)
      stored_state = raw_state.is_a?(Hash) ? raw_state.deep_stringify_keys : {}
      sanitized = default_state
      if definition.search_enabled? && stored_state["q"].is_a?(String)
        sanitized["q"] = stored_state["q"]
      end
      sanitized["filters"] = sanitize_filter_hash(stored_state["filters"]) if definition.filters_enabled?
      sanitized["columns_present"] = stored_state["columns_present"] == true
      sanitized["columns"] = sanitize_column_keys(stored_state["columns"]) if sanitized["columns_present"]
      sanitized["per_page"] = normalize_per_page(stored_state["per_page"])
      sanitized["sort_column"] = stored_state["sort_column"] if stored_state["sort_column"].is_a?(String)
      sanitized["sort_direction"] = stored_state["sort_direction"] if stored_state["sort_direction"].is_a?(String)
      sanitized["page"] = positive_integer(stored_state["page"]) || 1
      sanitize_sort!(sanitized)
      sanitized
    end

    def apply_query_request!
      changed = false

      if definition.search_enabled? && parameter_present?(:q) && parameter(:q).is_a?(String)
        changed |= assign_if_changed("q", parameter(:q))
      end

      if parameter_present?(:per_page)
        changed |= assign_if_changed("per_page", normalize_per_page(parameter(:per_page)))
      end

      requested_filters = if !definition.filters_enabled?
        nil
      elsif parameter(:clear_filters).present?
        {}
      elsif parameter_present?(:filters)
        sanitize_filter_hash(parameter(:filters))
      end
      changed |= assign_if_changed("filters", requested_filters) if requested_filters
      changed
    end

    def apply_columns_request!
      return unless parameter(:columns_present).present? || parameter_present?(:columns)

      @state["columns_present"] = true
      @state["columns"] = sanitize_column_keys(parameter(:columns))
    end

    def apply_sort_request!
      return false unless parameter_present?(:sort_column) && parameter_present?(:sort_state)

      requested_column_key = parameter(:sort_column)
      requested_state = parameter(:sort_state)
      return false unless requested_column_key.is_a?(String) && requested_state.is_a?(String)

      requested_column = definition.column(requested_column_key)
      return false unless requested_column&.sortable?
      return false unless selected_column_keys.include?(requested_column.key)
      return false unless SORT_STATES.include?(requested_state)
      return false unless requested_state == current_sort_state(requested_column.key)

      next_state = SORT_CYCLE.fetch(requested_state)
      if next_state == "default"
        @state["sort_column"] = nil
        @state["sort_direction"] = nil
      else
        @state["sort_column"] = requested_column.key
        @state["sort_direction"] = next_state
      end
      true
    end

    def sanitize_sort!(candidate_state)
      sort_column = candidate_state["sort_column"]
      sort_direction = candidate_state["sort_direction"]
      configured_column = definition.column(sort_column)
      valid = configured_column&.sortable? &&
        selected_column_keys_for(candidate_state).include?(configured_column.key) &&
        SORT_DIRECTIONS.include?(sort_direction)

      candidate_state["sort_column"] = valid ? configured_column.key : nil
      candidate_state["sort_direction"] = valid ? sort_direction : nil
    end

    def current_sort_state(column_key)
      @state["sort_column"] == column_key ? @state["sort_direction"] : "default"
    end

    def selected_column_keys_for(candidate_state)
      if candidate_state["columns_present"] == true
        candidate_state.fetch("columns", [])
      else
        definition.default_column_keys
      end
    end

    def sanitize_column_keys(raw_columns)
      values = case raw_columns
      when Array
        raw_columns
      when String
        [ raw_columns ]
      else
        []
      end

      values.select { |value| value.is_a?(String) }.uniq.intersection(definition.available_column_keys)
    end

    def sanitize_filter_hash(raw_filters)
      return {} unless keyed_object?(raw_filters)

      definition.filterable_columns.each_with_object({}) do |column, sanitized|
        raw_filter = object_value(raw_filters, column.key)
        next unless keyed_object?(raw_filter)

        permitted_filter = column.filter.permitted_fields.each_with_object({}) do |field, permitted|
          permitted[field.to_s] = object_value(raw_filter, field) if object_key?(raw_filter, field)
        end
        normalized_filter = column.normalize_filter(permitted_filter)
        sanitized[column.key] = normalized_filter if normalized_filter.present?
      end
    end

    def normalize_per_page(value)
      requested = positive_integer(value)
      definition.page_size_options.include?(requested) ? requested : definition.default_page_size
    end

    def positive_integer(value)
      return unless value.is_a?(String) || value.is_a?(Integer)

      integer = Integer(value, exception: false)
      integer if integer&.positive?
    end

    def assign_if_changed(key, value)
      return false if @state[key] == value

      @state[key] = value
      true
    end

    def parameter_present?(key)
      object_key?(params, key)
    end

    def parameter(key)
      object_value(params, key)
    end

    def keyed_object?(value)
      value.respond_to?(:key?) && value.respond_to?(:[])
    end

    def object_key?(object, key)
      return false unless keyed_object?(object)

      object.key?(key) || object.key?(key.to_s) || object.key?(key.to_sym)
    end

    def object_value(object, key)
      return unless keyed_object?(object)

      return object[key] if object.key?(key)
      return object[key.to_s] if object.key?(key.to_s)

      object[key.to_sym] if object.key?(key.to_sym)
    end
  end
end
