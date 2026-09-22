module LibraryFolderOperations
  class Remove
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
          mark_content_removed!(placement:, library_version:, user:, batch_key:)
        end
        selection.selected_folders.each do |folder|
          mark_folder_removed!(
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

    def self.remove_unused_manifests(library_version:, content_ids:)
      return if content_ids.empty?

      placed_content_ids = library_version.library_folder_contents
        .where(content_id: content_ids)
        .distinct
        .pluck(:content_id)
      unused_content_ids = content_ids - placed_content_ids
      library_version.library_version_contents.where(content_id: unused_content_ids).destroy_all
    end

    class << self
      private

      def mark_content_removed!(placement:, library_version:, user:, batch_key:)
        resource_key = LibraryChanges::Recorder.content_key(
          placement.library_folder_id,
          placement.content_id
        )
        change = LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :remove_content,
          batch_key:,
          details: {
            placement_id: placement.id,
            folder_id: placement.library_folder_id,
            content_id: placement.content_id
          },
          targets: [ content_target(placement:, direct: true) ],
          dependency_resource_keys: [ resource_key ]
        )
        placement.update!(pending_removal_change: change)
      end

      def mark_folder_removed!(selection:, folder:, library_version:, user:, batch_key:)
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
        dependency_change_ids = library_version.library_changes.pending
          .joins(:library_change_targets)
          .where(library_change_targets: { folder_id: folder_ids })
          .distinct
          .pluck(:id)

        change = LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :remove_folder,
          batch_key:,
          details: {
            root_folder_id: folder.id,
            source_parent_folder_id: folder.parent_folder_id,
            folder_ids:,
            placement_ids: placements.map(&:id),
            content_ids: placements.map(&:content_id).uniq
          },
          targets:,
          dependency_resource_keys: dependency_keys,
          dependency_change_ids:
        )

        LibraryFolder.where(id: folder_ids).update_all(
          pending_removal_change_id: change.id,
          updated_at: Time.current
        )
        LibraryFolderContent.where(id: placements.map(&:id)).update_all(
          pending_removal_change_id: change.id,
          updated_at: Time.current
        )
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
    end
  end
end
