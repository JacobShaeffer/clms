module LibraryFolderOperations
  class Remove
    FOLDER_SNAPSHOT_ATTRIBUTES = %w[
      id library_id library_version_id parent_folder_id user_id logo_id name created_at updated_at
    ].freeze
    PLACEMENT_SNAPSHOT_ATTRIBUTES = %w[
      id library_folder_id content_id library_version_id created_at updated_at
    ].freeze

    def self.call(library:, source_folder_id:, folder_ids:, content_ids:, user:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        selection = Selection.new(
          library:,
          library_version:,
          source_folder_id:,
          folder_ids:,
          content_ids:
        )
        batch_key = SecureRandom.uuid

        selection.direct_content_placements.each do |placement|
          remove_content!(placement:, library_version:, user:, batch_key:)
        end
        selection.selected_folders.each do |folder|
          remove_folder!(
            selection:,
            folder:,
            library_version:,
            user:,
            batch_key:
          )
        end

        selection
      end
    end

    class << self
      private

      def remove_content!(placement:, library_version:, user:, batch_key:)
        resource_key = LibraryChanges::Recorder.content_key(
          placement.library_folder_id,
          placement.content_id
        )
        LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :remove_content,
          batch_key:,
          details: {
            placement_id: placement.id,
            folder_id: placement.library_folder_id,
            content_id: placement.content_id,
            placement_snapshot: snapshot(placement, PLACEMENT_SNAPSHOT_ATTRIBUTES)
          },
          targets: [ content_target(placement:, direct: true) ],
          dependency_resource_keys: [ resource_key ]
        )
        placement.destroy!
      end

      def remove_folder!(selection:, folder:, library_version:, user:, batch_key:)
        folders = subtree_folders(selection, folder)
        folder_ids = folders.map(&:id)
        placements = selection.subtree_content_placements.select do |placement|
          folder_ids.include?(placement.library_folder_id)
        end
        targets = folders.map do |subtree_folder|
          folder_target(folder: subtree_folder, direct: subtree_folder.id == folder.id)
        end
        targets.concat(placements.map { |placement| content_target(placement:, direct: false) })
        dependency_keys = targets.map { |target| target.fetch(:resource_key) }
        targets << parent_context_target(folder.parent_folder) if folder.parent_folder
        dependency_change_ids = library_version.library_changes.not_undone
          .joins(:library_change_targets)
          .where(library_change_targets: { folder_id: folder_ids })
          .distinct
          .pluck(:id)

        LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :remove_folder,
          batch_key:,
          details: {
            root_folder_id: folder.id,
            source_parent_folder_id: folder.parent_folder_id,
            folder_ids:,
            placement_ids: placements.map(&:id),
            content_ids: placements.map(&:content_id).uniq,
            folder_snapshots: folders.map { |record| snapshot(record, FOLDER_SNAPSHOT_ATTRIBUTES) },
            placement_snapshots: placements.map do |record|
              snapshot(record, PLACEMENT_SNAPSHOT_ATTRIBUTES)
            end
          },
          targets:,
          dependency_resource_keys: dependency_keys,
          dependency_change_ids:
        )

        placements.each(&:destroy!)
        folders.reverse_each(&:destroy!)
      end

      def subtree_folders(selection, root)
        result = []
        collect = lambda do |current|
          result << current
          selection.children_for(current).each { |child| collect.call(child) }
        end
        collect.call(root)
        result
      end

      def folder_target(folder:, direct:)
        {
          target_kind: :folder,
          target_id: folder.id,
          folder_id: folder.id,
          resource_key: LibraryChanges::Recorder.folder_key(folder),
          effect: :removed,
          direct:,
          label: folder.name
        }
      end

      def parent_context_target(folder)
        folder_target(folder:, direct: false).merge(
          details: { display: false, context: "source_parent" }
        )
      end

      def content_target(placement:, direct:)
        {
          target_kind: :content,
          target_id: placement.id,
          folder_id: placement.library_folder_id,
          content_id: placement.content_id,
          resource_key: LibraryChanges::Recorder.content_key(
            placement.library_folder_id,
            placement.content_id
          ),
          effect: :removed,
          direct:,
          label: placement.content.title
        }
      end

      def snapshot(record, attributes)
        record.attributes.slice(*attributes).tap do |values|
          values["created_at"] = record.created_at.iso8601(6)
          values["updated_at"] = record.updated_at.iso8601(6)
        end
      end
    end
  end
end
