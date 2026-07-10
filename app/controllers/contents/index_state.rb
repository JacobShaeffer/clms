module Contents
  class IndexState
    SESSION_KEY = "contents_index_state"

    attr_reader :available_columns, :default_column_keys, :per_page_options

    def initialize(session:, params:, available_columns:, default_column_keys:, per_page_options:, default_per_page:)
      @session = session
      @params = params
      @available_columns = available_columns
      @default_column_keys = default_column_keys
      @per_page_options = per_page_options
      @default_per_page = default_per_page
      @state = nil
    end

    def reset!
      @state = default_state
      session.delete(SESSION_KEY)
    end

    def update!
      next_state = reset_requested? ? default_state : sanitized_session_state

      if clear_filters_requested?
        next_state["filters"] = {}
      end

      next_state["q"] = params[:q].to_s if params.key?(:q)
      next_state["per_page"] = normalized_per_page(params[:per_page]) if params.key?(:per_page)

      if columns_params_present?
        next_state["columns_present"] = true
        next_state["columns"] = requested_column_keys
      end

      next_state["filters"] = sanitized_filter_params if params.key?(:filters) && !clear_filters_requested?

      @state = next_state
      session[SESSION_KEY] = @state
    end

    def q
      state["q"].to_s
    end

    def filters
      state["filters"] || {}
    end

    def per_page
      normalized_per_page(state["per_page"])
    end

    def columns_present?
      state["columns_present"] == true
    end

    def selected_column_keys
      return default_column_keys unless columns_present?

      Array(state["columns"]) & available_column_keys
    end

    private

    attr_reader :session, :params

    def state
      @state ||= sanitized_session_state
    end

    def default_state
      {
        "q" => "",
        "filters" => {},
        "columns_present" => false,
        "columns" => [],
        "per_page" => @default_per_page
      }
    end

    def sanitized_session_state
      stored_state = session[SESSION_KEY].is_a?(Hash) ? session[SESSION_KEY] : {}
      next_state = default_state.merge(stored_state)

      next_state["q"] = next_state["q"].to_s
      next_state["filters"] = sanitize_filter_hash(next_state["filters"])
      next_state["columns_present"] = next_state["columns_present"] == true
      next_state["columns"] = Array(next_state["columns"]).map(&:to_s) & available_column_keys
      next_state["per_page"] = normalized_per_page(next_state["per_page"])
      next_state
    end

    def normalized_per_page(value)
      per_page = value.to_i

      per_page_options.include?(per_page) ? per_page : @default_per_page
    end

    def reset_requested?
      params[:reset_contents_state].present?
    end

    def clear_filters_requested?
      params[:clear_filters].present?
    end

    def columns_params_present?
      params[:columns_present].present? || params.key?(:columns)
    end

    def requested_column_keys
      Array(params[:columns]).filter_map { |column_key| column_key.to_s.presence } & available_column_keys
    end

    def available_column_keys
      available_columns.map { |column| column[:key] }
    end

    def sanitized_filter_params
      filter_params = params[:filters]
      return {} unless filter_params.respond_to?(:permit)

      permitted_shape = available_column_keys.map { |column_key| { column_key => %i[value from to] } }
      sanitize_filter_hash(filter_params.permit(*permitted_shape).to_h)
    end

    def sanitize_filter_hash(raw_filters)
      return {} unless raw_filters.is_a?(Hash)

      available_columns.each_with_object({}) do |column, filters|
        raw_filter = raw_filters[column[:key]]
        next unless raw_filter.is_a?(Hash)

        filter = normalized_filter(column, raw_filter)
        filters[column[:key]] = filter if filter.present?
      end
    end

    def normalized_filter(column, raw_filter)
      if column[:filter] == :date
        raw_filter.slice("from", "to").transform_values { |value| value.to_s.strip }.compact_blank
      else
        value = raw_filter["value"].to_s.strip
        value.present? ? { "value" => value } : {}
      end
    end
  end
end
