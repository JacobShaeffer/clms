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
          raise InvalidResolution,
            "Undo #{blocker.display_label} before undoing this change."
        end

        undo_change!
        change.update!(status: :undone, resolved_by: user, resolved_at: Time.current)
      end
      change
    end

    private

    attr_reader :change, :user

    def ensure_resolvable!(library)
      author_can_manage = change.user_id == user&.id &&
        LibraryFolderPolicy.new(user, LibraryFolder).manage?
      allowed = user&.admin? || author_can_manage
      raise InvalidResolution, "You cannot undo this library change." unless allowed
      raise InvalidResolution, "This change has already been resolved." unless change.pending?
      unless library.current_version_id == change.library_version_id && change.library_version.editable?
        raise InvalidResolution, "Only changes in the editable current version can be undone."
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
      LibraryFolder.where(
        id: Array(detail("folder_ids")),
        pending_removal_change_id: change.id
      ).update_all(pending_removal_change_id: nil, updated_at: Time.current)
      LibraryFolderContent.where(
        id: Array(detail("placement_ids")),
        pending_removal_change_id: change.id
      ).update_all(pending_removal_change_id: nil, updated_at: Time.current)
    end

    def undo_removed_content!
      LibraryFolderContent.where(
        id: detail("placement_id"),
        pending_removal_change_id: change.id
      ).update_all(pending_removal_change_id: nil, updated_at: Time.current)
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

    def detail(key)
      change.details.fetch(key)
    end
  end
end
