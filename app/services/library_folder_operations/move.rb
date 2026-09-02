module LibraryFolderOperations
  class Move
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:, destination_folder_id:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        selection = Selection.new(
          library:,
          library_version:,
          source_folder_id:,
          folder_ids:,
          content_ids:
        )
        destination = selection.destination!(destination_folder_id, operation: :move)
        content_ids_to_move = selection.direct_content_placements.map(&:content_id)
        PlaceContents.place_for_version!(
          library_version:,
          folder: destination,
          content_ids: content_ids_to_move
        )

        selection.direct_content_placements.each(&:destroy!)
        selection.selected_folders.each do |folder|
          folder.update!(parent_folder: destination, logo: nil)
        end

        selection
      end
    end
  end
end
