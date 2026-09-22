module LibraryFolderOperations
  class PlaceContents
    Result = Struct.new(
      :status,
      :missing_content_ids,
      :existing_content_ids,
      :added_placements,
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

    def self.call(library:, folder_id:, content_ids:, user:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        folder = library_version.library_folders.active.find(folder_id)
        batch_key = SecureRandom.uuid

        result = place_for_version!(
          library_version:,
          folder:,
          content_ids:
        )

        result.added_placements.each do |placement|
          LibraryChanges::Recorder.call(
            library_version:,
            user:,
            action_type: :add_content,
            batch_key:,
            details: {
              placement_id: placement.id,
              folder_id: folder.id,
              content_id: placement.content_id
            },
            targets: [ content_target(placement, effect: :new) ],
            required_folder_ids: [ folder.id ]
          )
        end

        result
      end
    end

    def self.place_for_version!(library_version:, folder:, content_ids:)
      ensure_editable_current_folder!(library_version:, folder:)

      normalized_content_ids = normalize_content_ids(content_ids)
      if folder.library_folder_contents
        .where(content_id: normalized_content_ids)
        .where.not(pending_removal_change_id: nil)
        .exists?
        raise Selection::InvalidSelection, "Content pending removal cannot be changed."
      end
      existing_content_ids = folder.library_folder_contents.active
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

        added_placements = missing_content_ids.map do |content_id|
          folder.library_folder_contents.create!(
            library_version:,
            content_id:
          )
        end
      else
        added_placements = []
      end

      Result.new(
        status: result_status(missing_content_ids:, existing_content_ids:),
        missing_content_ids:,
        existing_content_ids:,
        added_placements:
      )
    end

    class << self
      private

      def content_target(placement, effect:, direct: true)
        {
          target_kind: :content,
          target_id: placement.id,
          folder_id: placement.library_folder_id,
          content_id: placement.content_id,
          resource_key: LibraryChanges::Recorder.content_key(
            placement.library_folder_id,
            placement.content_id
          ),
          effect:,
          direct:,
          label: placement.content.title
        }
      end

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
