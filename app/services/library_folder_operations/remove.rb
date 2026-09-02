module LibraryFolderOperations
  class Remove
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:)
      library.with_lock do
        selection = Selection.new(library:, source_folder_id:, folder_ids:, content_ids:)

        (selection.direct_content_placements + selection.subtree_content_placements)
          .uniq(&:id)
          .each(&:destroy!)
        selection.subtree_folders.reverse_each(&:destroy!)

        selection
      end
    end
  end
end
