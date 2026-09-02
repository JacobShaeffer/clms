module LibraryFolderOperations
  class Remove
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        selection = Selection.new(
          library:,
          library_version:,
          source_folder_id:,
          folder_ids:,
          content_ids:
        )
        placements = (selection.direct_content_placements + selection.subtree_content_placements)
          .uniq(&:id)
        affected_content_ids = placements.map(&:content_id).uniq

        placements.each(&:destroy!)
        selection.subtree_folders.reverse_each(&:destroy!)
        remove_unused_manifests(library_version:, content_ids: affected_content_ids)

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

    private_class_method :remove_unused_manifests
  end
end
