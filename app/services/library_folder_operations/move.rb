module LibraryFolderOperations
  class Move
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
        destination = selection.destination!(destination_folder_id, operation: :move)
        batch_key = SecureRandom.uuid

        selection.direct_content_placements.each do |placement|
          move_content!(placement:, destination:, library_version:, user:, batch_key:)
        end
        selection.selected_folders.each do |folder|
          move_folder!(folder:, destination:, library_version:, user:, batch_key:)
        end

        selection
      end
    end

    class << self
      private

      def move_content!(placement:, destination:, library_version:, user:, batch_key:)
        source_folder_id = placement.library_folder_id
        content = placement.content
        destination_placement = destination.library_folder_contents.active.find_by(content_id: content.id)
        destination_created = destination_placement.nil?
        if destination_created
          destination_placement = PlaceContents.place_for_version!(
            library_version:,
            folder: destination,
            content_ids: [ content.id ]
          ).added_placements.fetch(0)
        end

        source_placement_id = placement.id
        placement.destroy!
        source_key = LibraryChanges::Recorder.content_key(source_folder_id, content.id)
        destination_key = LibraryChanges::Recorder.content_key(destination.id, content.id)

        LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :move_content,
          batch_key:,
          details: {
            content_id: content.id,
            source_folder_id:,
            source_placement_id:,
            destination_folder_id: destination.id,
            destination_placement_id: destination_placement.id,
            destination_created:
          },
          targets: [
            content_target(
              placement_id: destination_placement.id,
              folder_id: destination.id,
              content:,
              resource_key: destination_key,
              direct: true
            ),
            content_target(
              placement_id: source_placement_id,
              folder_id: source_folder_id,
              content:,
              resource_key: source_key,
              direct: false
            )
          ],
          dependency_resource_keys: [ source_key, destination_key ],
          required_folder_ids: [ destination.id ]
        )
      end

      def move_folder!(folder:, destination:, library_version:, user:, batch_key:)
        previous_parent_folder_id = folder.parent_folder_id
        previous_logo_id = folder.logo_id
        resource_key = LibraryChanges::Recorder.folder_key(folder)
        source_parent = folder.parent_folder

        folder.update!(parent_folder: destination, logo: nil)
        targets = [ {
          target_kind: :folder,
          target_id: folder.id,
          folder_id: folder.id,
          resource_key:,
          effect: :moved,
          direct: true,
          label: folder.name
        } ]
        if source_parent
          targets << context_folder_target(source_parent, "source")
        end
        targets << context_folder_target(destination, "destination")

        LibraryChanges::Recorder.call(
          library_version:,
          user:,
          action_type: :move_folder,
          batch_key:,
          details: {
            folder_id: folder.id,
            source_parent_folder_id: previous_parent_folder_id,
            destination_folder_id: destination.id,
            source_logo_id: previous_logo_id
          },
          targets:,
          dependency_resource_keys: [ resource_key ],
          required_folder_ids: [ destination.id ]
        )
      end

      def context_folder_target(folder, context)
        {
          target_kind: :folder,
          target_id: folder.id,
          folder_id: folder.id,
          resource_key: LibraryChanges::Recorder.folder_key(folder),
          effect: :moved,
          direct: false,
          label: folder.name,
          details: {
            display: false,
            context:
          }
        }
      end

      def content_target(placement_id:, folder_id:, content:, resource_key:, direct:)
        {
          target_kind: :content,
          target_id: placement_id,
          folder_id:,
          content_id: content.id,
          resource_key:,
          effect: :moved,
          direct:,
          label: content.title
        }
      end
    end
  end
end
