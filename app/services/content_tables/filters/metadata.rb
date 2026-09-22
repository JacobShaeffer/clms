module ContentTables
  module Filters
    class Metadata < Base
      DEFAULT_INPUT_PARTIAL = "content_tables/filters/metadata"

      attr_reader :metadata_type

      def initialize(metadata_type:, input_partial: DEFAULT_INPUT_PARTIAL)
        @metadata_type = metadata_type
        super(
          attribute: nil,
          input_partial:,
          permitted_fields: [ :metadatum_ids ],
          apply: method(:apply_metadata)
        )
      end

      def normalize(raw_filter)
        requested_ids = normalize_ids(raw_value(raw_filter, "metadatum_ids"))
        return {} if requested_ids.empty?

        valid_ids = metadata_type.metadata.where(id: requested_ids).pluck(:id)
        selected_ids = requested_ids.intersection(valid_ids)
        selected_ids.any? ? { "metadatum_ids" => selected_ids } : {}
      end

      def selected_metadata(values)
        ids = normalize_ids(values["metadatum_ids"])
        metadata_by_id = metadata_type.metadata.where(id: ids).index_by(&:id)

        ids.filter_map { |id| metadata_by_id[id] }
      end

      private

      def normalize_ids(raw_ids)
        values = case raw_ids
        when Array
          raw_ids
        when String, Integer
          [ raw_ids ]
        else
          []
        end

        values
          .filter_map { |id| Integer(id, exception: false) }
          .select(&:positive?)
          .uniq
      end

      def apply_metadata(relation:, values:, **)
        selected_ids = normalize_ids(values["metadatum_ids"])
        return relation if selected_ids.empty?

        metadata_ids = metadata_type.metadata
          .where(id: selected_ids)
          .select(:id)
        matching_content_ids = ContentMetadatum
          .where(metadata_id: metadata_ids)
          .select(:content_id)

        relation.where(id: matching_content_ids)
      end
    end
  end
end
