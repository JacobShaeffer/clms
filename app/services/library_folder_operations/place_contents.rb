module LibraryFolderOperations
  class PlaceContents
    Result = Struct.new(
      :status,
      :missing_content_ids,
      :existing_content_ids,
      keyword_init: true
    ) do
      alias_method :added_content_ids, :missing_content_ids

      def none_added?
        missing_content_ids.empty?
      end

      def some_skipped?
        existing_content_ids.any?
      end
    end

    def self.call(library:, folder_id:, content_ids:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        folder = library_version.library_folders.find(folder_id)

        place_for_version!(
          library_version:,
          folder:,
          content_ids:
        )
      end
    end

    def self.place_for_version!(library_version:, folder:, content_ids:)
      ensure_editable_current_folder!(library_version:, folder:)

      normalized_content_ids = normalize_content_ids(content_ids)
      existing_content_ids = folder.library_folder_contents
        .where(library_version:, content_id: normalized_content_ids)
        .pluck(:content_id)
      missing_content_ids = normalized_content_ids - existing_content_ids

      if missing_content_ids.any?
        contents_by_id = Content
          .includes(file_attachment: :blob)
          .where(id: missing_content_ids)
          .index_by(&:id)
        if contents_by_id.length != missing_content_ids.length
          raise ActiveRecord::RecordNotFound, "One or more content items are unavailable."
        end

        missing_content_ids.each do |content_id|
          library_version.ensure_content_manifest!(contents_by_id.fetch(content_id))
        end

        LibraryFolderContent.insert_all(
          missing_content_ids.map do |content_id|
            {
              library_folder_id: folder.id,
              library_version_id: library_version.id,
              content_id:
            }
          end,
          unique_by: %i[library_folder_id content_id]
        )
      end

      Result.new(
        status: result_status(missing_content_ids:, existing_content_ids:),
        missing_content_ids:,
        existing_content_ids:
      )
    end

    class << self
      private

      def ensure_editable_current_folder!(library_version:, folder:)
        unless library_version.editable?
          raise Selection::InvalidSelection, "The current library version is locked."
        end
        unless folder.library_version_id == library_version.id
          raise Selection::InvalidSelection, "The destination folder is no longer available."
        end

        VersionGuard.ensure_current!(library: library_version.library, library_version:)
      end

      def normalize_content_ids(content_ids)
        Array(content_ids).map do |value|
          id = Integer(value, exception: false) if value.is_a?(String) || value.is_a?(Integer)
          unless id&.positive?
            raise Selection::InvalidSelection, "Invalid content selection."
          end

          id
        end.uniq
      end

      def result_status(missing_content_ids:, existing_content_ids:)
        return :already_present if missing_content_ids.empty?
        return :partially_added if existing_content_ids.any?

        :added
      end
    end
  end
end
