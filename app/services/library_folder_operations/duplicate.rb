module LibraryFolderOperations
  class Duplicate
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:, destination_folder_id:, user:)
      library.with_lock do
        library_version = VersionGuard.editable_current_version!(library)
        selection = Selection.new(
          library:,
          library_version:,
          source_folder_id:,
          folder_ids:,
          content_ids:
        )
        destination = selection.destination!(destination_folder_id, operation: :duplicate)

        copy_direct_content(selection, destination, library_version)
        selection.selected_folders.each do |folder|
          copy_folder_tree(
            selection:,
            source_folder: folder,
            parent_folder: destination,
            library:,
            library_version:,
            user:
          )
        end

        selection
      end
    end

    class << self
      private

      def copy_direct_content(selection, destination, library_version)
        content_ids = selection.direct_content_placements.map(&:content_id)
        PlaceContents.place_for_version!(
          library_version:,
          folder: destination,
          content_ids:
        )
      end

      def copy_folder_tree(selection:, source_folder:, parent_folder:, library:, library_version:, user:)
        copied_folder = library_version.library_folders.create!(
          library:,
          name: source_folder.name,
          parent_folder:,
          user:,
          logo: nil
        )
        content_ids = selection.placements_for(source_folder).map(&:content_id)
        PlaceContents.place_for_version!(
          library_version:,
          folder: copied_folder,
          content_ids:
        )
        selection.children_for(source_folder).each do |child|
          copy_folder_tree(
            selection:,
            source_folder: child,
            parent_folder: copied_folder,
            library:,
            library_version:,
            user:
          )
        end

        copied_folder
      end
    end
  end
end
