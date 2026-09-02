module LibraryFolderOperations
  class Duplicate
    def self.call(library:, source_folder_id:, folder_ids:, content_ids:, destination_folder_id:, user:)
      library.with_lock do
        selection = Selection.new(library:, source_folder_id:, folder_ids:, content_ids:)
        destination = selection.destination!(destination_folder_id, operation: :duplicate)

        copy_direct_content(selection, destination)
        selection.selected_folders.each do |folder|
          copy_folder_tree(selection:, source_folder: folder, parent_folder: destination, library:, user:)
        end

        selection
      end
    end

    class << self
      private

      def copy_direct_content(selection, destination)
        content_ids = selection.direct_content_placements.map(&:content_id)
        existing_content_ids = destination.library_folder_contents
          .where(content_id: content_ids)
          .pluck(:content_id)
        missing_content_ids = content_ids - existing_content_ids
        return if missing_content_ids.empty?

        LibraryFolderContent.insert_all(
          missing_content_ids.map { |content_id| { library_folder_id: destination.id, content_id: } },
          unique_by: %i[library_folder_id content_id]
        )
      end

      def copy_folder_tree(selection:, source_folder:, parent_folder:, library:, user:)
        copied_folder = library.library_folders.create!(
          name: source_folder.name,
          parent_folder:,
          user:,
          logo: nil
        )
        content_ids = selection.placements_for(source_folder).map(&:content_id)
        if content_ids.any?
          LibraryFolderContent.insert_all(
            content_ids.map { |content_id| { library_folder_id: copied_folder.id, content_id: } },
            unique_by: %i[library_folder_id content_id]
          )
        end
        selection.children_for(source_folder).each do |child|
          copy_folder_tree(
            selection:,
            source_folder: child,
            parent_folder: copied_folder,
            library:,
            user:
          )
        end

        copied_folder
      end
    end
  end
end
