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
        batch_key = SecureRandom.uuid

        duplicate_direct_content!(selection:, destination:, library_version:, user:, batch_key:)
        selection.selected_folders.each do |folder|
          duplicate_folder!(
            selection:,
            source_folder: folder,
            destination:,
            library:,
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

      def duplicate_direct_content!(selection:, destination:, library_version:, user:, batch_key:)
        selection.direct_content_placements.each do |source_placement|
          next if destination.library_folder_contents.active.exists?(content_id: source_placement.content_id)

          placement = PlaceContents.place_for_version!(
            library_version:,
            folder: destination,
            content_ids: [ source_placement.content_id ]
          ).added_placements.fetch(0)
          source_key = LibraryChanges::Recorder.content_key(
            source_placement.library_folder_id,
            source_placement.content_id
          )
          destination_key = LibraryChanges::Recorder.content_key(destination.id, placement.content_id)

          LibraryChanges::Recorder.call(
            library_version:,
            user:,
            action_type: :duplicate_content,
            batch_key:,
            details: {
              placement_id: placement.id,
              folder_id: destination.id,
              content_id: placement.content_id,
              source_folder_id: source_placement.library_folder_id
            },
            targets: [ content_target(placement:, direct: true) ],
            dependency_resource_keys: [ source_key, destination_key ],
            required_folder_ids: [ destination.id ]
          )
        end
      end

      def duplicate_folder!(selection:, source_folder:, destination:, library:, library_version:, user:, batch_key:)
        copied_folders = []
        copied_placements = []
        copied_root = copy_folder_tree(
          selection:,
          source_folder:,
          parent_folder: destination,
          library:,
          library_version:,
          user:,
          copied_folders:,
          copied_placements:
        )
        source_folder_ids = subtree_folder_ids(selection, source_folder)
        source_keys = source_folder_ids.map { |id| LibraryChanges::Recorder.folder_key(id) }
        selection.subtree_content_placements
          .select { |placement| source_folder_ids.include?(placement.library_folder_id) }
          .each do |placement|
            source_keys << LibraryChanges::Recorder.content_key(
              placement.library_folder_id,
              placement.content_id
            )
          end

        targets = copied_folders.map do |folder|
          folder_target(folder:, direct: folder.id == copied_root.id)
        end
        targets.concat(copied_placements.map { |placement| content_target(placement:, direct: false) })

        LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :duplicate_folder,
          batch_key:,
          details: {
            source_folder_id: source_folder.id,
            destination_folder_id: destination.id,
            root_folder_id: copied_root.id,
            folder_ids: copied_folders.map(&:id),
            placement_ids: copied_placements.map(&:id)
          },
          targets:,
          dependency_resource_keys: source_keys,
          required_folder_ids: [ destination.id ]
        )
      end

      def copy_folder_tree(
        selection:,
        source_folder:,
        parent_folder:,
        library:,
        library_version:,
        user:,
        copied_folders:,
        copied_placements:
      )
        copied_folder = library_version.library_folders.create!(
          library:,
          name: source_folder.name,
          parent_folder:,
          user:,
          logo: nil
        )
        copied_folders << copied_folder
        result = PlaceContents.place_for_version!(
          library_version:,
          folder: copied_folder,
          content_ids: selection.placements_for(source_folder).map(&:content_id)
        )
        copied_placements.concat(result.added_placements)
        selection.children_for(source_folder).each do |child|
          copy_folder_tree(
            selection:,
            source_folder: child,
            parent_folder: copied_folder,
            library:,
            library_version:,
            user:,
            copied_folders:,
            copied_placements:
          )
        end

        copied_folder
      end

      def subtree_folder_ids(selection, root)
        result = []
        collect = lambda do |folder|
          result << folder.id
          selection.children_for(folder).each { |child| collect.call(child) }
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
          effect: :new,
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
          effect: :new,
          direct:,
          label: placement.content.title
        }
      end
    end
  end
end
