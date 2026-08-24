module ContentTables
  class Definition
    attr_reader :state_key, :frame_id, :update_path, :reset_path, :source,
      :columns, :groups, :filter_groups, :default_column_keys, :page_size_options,
      :default_page_size, :empty_message, :quick_search, :default_order,
      :row_partial, :dom_prefix, :search_placeholder, :selection_form_id

    def initialize(
      state_key:,
      frame_id:,
      update_path:,
      reset_path:,
      source:,
      columns:,
      groups:,
      filter_groups: nil,
      default_column_keys:,
      page_size_options:,
      default_page_size:,
      empty_message:,
      quick_search:,
      default_order:,
      row_partial: nil,
      dom_prefix: nil,
      search_placeholder: "Search",
      search_enabled: true,
      filters_enabled: true,
      selectable: false,
      selection_form_id: nil
    )
      @state_key = state_key.to_s
      @frame_id = frame_id.to_s
      @update_path = update_path.to_s
      @reset_path = reset_path.to_s
      @source = source
      @columns = Array(columns).freeze
      @groups = normalize_groups(groups).freeze
      @filter_groups = normalize_groups(filter_groups || groups).freeze
      @page_size_options = Array(page_size_options).map(&:to_i).select(&:positive?).uniq.freeze
      @default_page_size = default_page_size.to_i
      @empty_message = empty_message.to_s
      @quick_search = quick_search
      @default_order = default_order
      @row_partial = row_partial&.to_s
      @dom_prefix = (dom_prefix.presence || derived_dom_prefix).to_s
      @search_placeholder = search_placeholder.to_s
      @search_enabled = search_enabled == true
      @filters_enabled = filters_enabled == true
      @selectable = selectable == true
      @selection_form_id = selection_form_id&.to_s
      @columns_by_key = @columns.index_by(&:key).freeze
      @default_column_keys = Array(default_column_keys).map(&:to_s).uniq.intersection(available_column_keys).freeze

      validate!
    end

    def column(key)
      @columns_by_key[key.to_s]
    end

    def available_column_keys
      @columns_by_key.keys
    end

    def filterable_columns
      return [] unless filters_enabled?

      columns.select(&:filterable?)
    end

    def search_enabled?
      @search_enabled
    end

    def filters_enabled?
      @filters_enabled
    end

    def selectable?
      @selectable
    end

    def columns_for_group(group)
      columns.select { |column| column.group == group.to_sym }
    end

    def columns_for_filter_group(group)
      configured_group = filter_groups.find { |candidate| candidate.fetch(:key) == group.to_sym }
      return [] unless configured_group

      column_keys = configured_group[:column_keys]
      return columns_for_group(group) unless column_keys

      column_keys.filter_map { |key| column(key) }
    end

    def selected_columns(keys)
      selected_keys = Array(keys).map(&:to_s)
      columns.select { |column| selected_keys.include?(column.key) }
    end

    def dom_id(suffix)
      [ dom_prefix, suffix.to_s.dasherize ].reject(&:blank?).join("-")
    end

    def update_url(params = {})
      query = Rack::Utils.build_nested_query(params.to_h)
      return update_path if query.blank?

      "#{update_path}#{update_path.include?("?") ? "&" : "?"}#{query}"
    end

    def relation_for(state)
      relation = source.respond_to?(:call) ? source.call : source
      relation = quick_search.call(relation:, query: state.q) if state.q.present?

      state.filters.each do |column_key, values|
        configured_column = column(column_key)
        next unless configured_column&.filterable?

        relation = configured_column.apply_filter(relation:, values:)
      end

      sorted_column = column(state.sort_column)
      if sorted_column&.sortable? && state.selected_column_keys.include?(sorted_column.key)
        sorted_column.apply_sort(relation:, direction: state.sort_direction)
      else
        default_order.call(relation:)
      end
    end

    private

    def normalize_groups(raw_groups)
      Array(raw_groups).map do |group|
        values = group.respond_to?(:to_h) ? group.to_h.symbolize_keys : {}
        key = values.fetch(:key).to_sym
        label = key.to_s.humanize

        values.merge(
          key:,
          columns_label: values[:columns_label].presence || "#{label} columns",
          filters_label: values[:filters_label].presence || "#{label} filters"
        ).freeze
      end
    end

    def derived_dom_prefix
      frame_id.dasherize.sub(/-table\z/, "")
    end

    def validate!
      raise ArgumentError, "state_key is required" if state_key.blank?
      raise ArgumentError, "frame_id is required" if frame_id.blank?
      raise ArgumentError, "update_path is required" if update_path.blank?
      raise ArgumentError, "reset_path is required" if reset_path.blank?
      raise ArgumentError, "source is required" if source.nil?
      raise ArgumentError, "columns must contain ContentTables::Column objects" unless columns.all? { |column| column.is_a?(Column) }
      raise ArgumentError, "column keys must be unique" unless available_column_keys.size == columns.size
      raise ArgumentError, "group keys must be unique" unless groups.map { |group| group.fetch(:key) }.uniq.size == groups.size
      raise ArgumentError, "filter group keys must be unique" unless filter_groups.map { |group| group.fetch(:key) }.uniq.size == filter_groups.size
      raise ArgumentError, "every column group must be configured" unless columns.all? { |column| groups.any? { |group| group.fetch(:key) == column.group } }
      raise ArgumentError, "page_size_options cannot be empty" if page_size_options.empty?
      raise ArgumentError, "default_page_size must be an option" unless page_size_options.include?(default_page_size)
      raise ArgumentError, "quick_search must be callable" unless quick_search.respond_to?(:call)
      raise ArgumentError, "default_order must be callable" unless default_order.respond_to?(:call)
    end
  end
end
