module ContentTables
  class Issues
    INTRINSIC_FIELDS = {
      title: "Title",
      display_title: "Display Title",
      description: "Description"
    }.freeze
    RIGHTS_METADATA_NAMES = [ "rights holder", "rights statement" ].freeze
    DANGER_THRESHOLD = 4

    def self.rights_metadata_type?(type)
      RIGHTS_METADATA_NAMES.include?(type.name.squish.downcase)
    end

    def initialize(content:, metadata_types:)
      @content = content
      @metadata_types = metadata_types
    end

    def missing_fields
      @missing_fields ||= begin
        fields = missing_intrinsic_fields.map { |attribute| INTRINSIC_FIELDS.fetch(attribute) }
        fields << "File" if file_missing?
        fields + missing_metadata_types.map(&:name)
      end
    end

    def severity
      missing_count = missing_intrinsic_fields.size + (file_missing? ? 1 : 0) + missing_metadata_types.size
      return if missing_count.zero?

      if missing_count >= DANGER_THRESHOLD || missing_metadata_types.any? { |type| self.class.rights_metadata_type?(type) }
        :danger
      else
        :warning
      end
    end

    private

    attr_reader :content, :metadata_types

    def missing_intrinsic_fields
      @missing_intrinsic_fields ||= INTRINSIC_FIELDS.keys.select { |attribute| content.public_send(attribute).blank? }
    end

    def file_missing?
      !content.file.attached?
    end

    def missing_metadata_types
      @missing_metadata_types ||= begin
        assigned_type_ids = content.metadata.map(&:metadata_type_id)
        metadata_types.reject { |type| assigned_type_ids.include?(type.id) }
      end
    end
  end
end
