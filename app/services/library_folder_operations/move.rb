module LibraryFolderOperations
  class Move
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:, destination_folder_id:)
      library.with_lock do
        selection = Selection.new(library:, source_folder_id:, folder_ids:, content_ids:)
        destination = selection.destination!(destination_folder_id, operation: :move)
        content_ids_to_move = selection.direct_content_placements.map(&:content_id)
        existing_content_ids = destination.library_folder_contents
          .where(content_id: content_ids_to_move)
          .pluck(:content_id)
        missing_content_ids = content_ids_to_move - existing_content_ids

        if missing_content_ids.any?
          LibraryFolderContent.insert_all(
            missing_content_ids.map { |content_id| { library_folder_id: destination.id, content_id: } },
            unique_by: %i[library_folder_id content_id]
          )
        end

        selection.direct_content_placements.each(&:destroy!)
        selection.selected_folders.each do |folder|
          folder.update!(parent_folder: destination, logo: nil)
        end

        selection
      end
    end
  end
end
