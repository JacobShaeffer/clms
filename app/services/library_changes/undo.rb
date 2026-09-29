module LibraryChanges
  class Undo
    def self.call(change:, user:)
      new(change:, user:).call
    end

    def initialize(change:, user:)
      @change = change
      @user = user
    end

    def call
      library = change.library_version.library
      library.with_lock do
        change.lock!
        ensure_resolvable!(library)
        blocker = change.undo_blocker
        if blocker
          raise InvalidUndo,
            "Undo #{blocker.display_label} before undoing this change."
        end

        undo_change!
        change.update!(undone_by: user, undone_at: Time.current)
      end
      change
    end

    private

    attr_reader :change, :user

    def ensure_resolvable!(library)
      author_can_manage = change.user_id == user&.id &&
        LibraryFolderPolicy.new(user, LibraryFolder).manage?
      allowed = user&.admin? || author_can_manage
      raise InvalidUndo, "You cannot undo this library change." unless allowed
      raise InvalidUndo, "This library change has already been undone." if change.undone?
      unless library.current_version_id == change.library_version_id && change.library_version.editable?
        raise InvalidUndo, "Only changes in the editable current version can be undone."
      end
    end

    def undo_change!
      case change.action_type.to_sym
      when :add_folder then undo_added_folder!
      when :add_content then undo_added_content!
      when :move_folder then undo_moved_folder!
      when :move_content then undo_moved_content!
      when :remove_folder then undo_removed_folder!
      when :remove_content then undo_removed_content!
      when :duplicate_folder then undo_duplicated_folder!
      when :duplicate_content then undo_duplicated_content!
      end
    end

    def undo_added_folder!
      LibraryFolder.find_by(id: detail("folder_id"))&.destroy!
    end

    def undo_added_content!
      find_placement(detail("folder_id"), detail("content_id"))&.destroy!
    end

    def undo_moved_folder!
      folder = LibraryFolder.find(detail("folder_id"))
      folder.update!(
        parent_folder_id: detail("source_parent_folder_id"),
        logo_id: detail("source_logo_id")
      )
    end

    def undo_moved_content!
      if detail("destination_created")
        find_placement(detail("destination_folder_id"), detail("content_id"))&.destroy!
      end
      return if find_placement(detail("source_folder_id"), detail("content_id"))

      LibraryFolderContent.create!(
        id: detail("source_placement_id"),
        library_version: change.library_version,
        library_folder_id: detail("source_folder_id"),
        content_id: detail("content_id")
      )
    end

    def undo_removed_folder!
      Array(detail("folder_snapshots")).each do |snapshot|
        LibraryFolder.create!(snapshot.slice(*folder_snapshot_attributes))
      end
      restore_placements!(detail("placement_snapshots"))
    end

    def undo_removed_content!
      restore_placements!([ detail("placement_snapshot") ])
    end

    def undo_duplicated_folder!
      LibraryFolderContent.where(id: Array(detail("placement_ids"))).find_each(&:destroy!)
      Array(detail("folder_ids")).reverse_each do |folder_id|
        LibraryFolder.find_by(id: folder_id)&.destroy!
      end
    end

    def undo_duplicated_content!
      find_placement(detail("folder_id"), detail("content_id"))&.destroy!
    end

    def find_placement(folder_id, content_id)
      change.library_version.library_folder_contents.find_by(
        library_folder_id: folder_id,
        content_id:
      )
    end

    def restore_placements!(snapshots)
      Array(snapshots).each do |snapshot|
        LibraryFolderContent.create!(snapshot.slice(*placement_snapshot_attributes))
      end
    end

    def folder_snapshot_attributes
      %w[id library_id library_version_id parent_folder_id user_id logo_id name created_at updated_at]
    end

    def placement_snapshot_attributes
      %w[id library_folder_id content_id library_version_id created_at updated_at]
    end

    def detail(key)
      change.details.fetch(key)
    end
  end
end
