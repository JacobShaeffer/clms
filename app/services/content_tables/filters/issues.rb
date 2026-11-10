module ContentTables
  module Filters
    class Issues < Base
      OPTIONS = [
        { value: "", label: "All Content", flags: [] },
        { value: "none", label: "No Issues", flags: [] },
        { value: "warning", label: "Yellow Flags Only", flags: [ :warning ] },
        { value: "danger", label: "Red Flags Only", flags: [ :danger ] },
        { value: "any", label: "Has an Issue", flags: [ :warning, :danger ] }
      ].freeze
      VALUES = %w[none warning danger any].freeze
      # Match String#blank?, including Unicode spaces not recognized by every PostgreSQL locale.
      BLANK_PATTERN = "^[[:space:]\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]*$"

      def initialize(metadata_types:)
        @metadata_type_ids = metadata_types.map(&:id)
        @rights_type_ids = metadata_types.select { |type| ContentTables::Issues.rights_metadata_type?(type) }.map(&:id)
        super(attribute: nil, input_partial: "content_tables/filters/issues", permitted_fields: [ :value ], apply: method(:apply_issues))
      end

      def normalize(raw_filter)
        value = raw_value(raw_filter, "value")
        return {} unless value.is_a?(String) && VALUES.include?(value.strip)

        { "value" => value.strip }
      end

      def selected_option(values)
        OPTIONS.find { |option| option[:value] == values["value"] } || OPTIONS.first
      end

      private

      def apply_issues(relation:, values:, **)
        count = missing_count
        critical = present_type_count(@rights_type_ids).lt(@rights_type_ids.size) if @rights_type_ids.any?
        predicate = case values["value"]
        when "none"
          count.eq(0)
        when "warning"
          warning = count.between(1..(ContentTables::Issues::DANGER_THRESHOLD - 1))
          critical ? warning.and(critical.not) : warning
        when "danger"
          danger = count.gteq(ContentTables::Issues::DANGER_THRESHOLD)
          critical ? danger.or(critical) : danger
        when "any"
          count.gt(0)
        else
          return relation
        end

        relation.where(predicate)
      end

      def missing_count
        contents = Content.arel_table
        expressions = ContentTables::Issues::INTRINSIC_FIELDS.keys.map do |attribute|
          blank = contents[attribute].eq(nil).or(contents[attribute].matches_regexp(BLANK_PATTERN))
          Arel::Nodes::Case.new.when(blank).then(1).else(0)
        end
        attachments = ActiveStorage::Attachment.arel_table
        attached_file = attachments.project(attachments[:id])
          .where(attachments[:record_type].eq(Content.polymorphic_name))
          .where(attachments[:record_id].eq(contents[:id]))
          .where(attachments[:name].eq("file")).exists
        expressions << Arel::Nodes::Case.new.when(attached_file).then(0).else(1)
        expressions << Arel::Nodes::Subtraction.new(Arel::Nodes.build_quoted(@metadata_type_ids.size), present_type_count(@metadata_type_ids))
        expressions.reduce { |sum, expression| sum + expression }
      end

      def present_type_count(type_ids)
        return Arel::Nodes.build_quoted(0) if type_ids.empty?

        assignments = ContentMetadatum.arel_table
        metadata = Metadatum.arel_table
        count = Arel::Nodes::Count.new([ metadata[:metadata_type_id] ], true)
        query = assignments.project(count)
          .join(metadata).on(metadata[:id].eq(assignments[:metadata_id]))
          .where(assignments[:content_id].eq(Content.arel_table[:id]))
          .where(metadata[:metadata_type_id].in(type_ids))
        Arel::Nodes::Grouping.new(query.ast)
      end
    end
  end
end
