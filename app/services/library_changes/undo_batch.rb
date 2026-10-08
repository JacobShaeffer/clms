module LibraryChanges
  class UndoBatch
    def self.call(changes:, user:, library:)
      library.with_lock do
        changes.each(&:reload)
        validate!(changes:, user:, library:)
        undo_group_key = SecureRandom.uuid
        changes.sort_by(&:id).reverse_each { |change| Undo.call(change:, user:, undo_group_key:) }
      end
      changes
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordNotFound,
        ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotUnique
      raise InvalidUndo, "This edit is blocked because required library data has changed."
    end

    def self.validate!(changes:, user:, library:)
      unless changes.any? && LibraryFolderPolicy.new(user, LibraryFolder).manage? &&
          changes.all? { |change| change.user_id == user.id }
        raise InvalidUndo, "Only your own edits can be undone from this page."
      end
      version = changes.first.library_version
      unless library.current_version_id == version.id && version.reload.editable?
        raise InvalidUndo, "Only changes in the editable current version can be undone."
      end
      raise InvalidUndo, "This edit has already been undone elsewhere." if changes.any?(&:undone?)
      ids = changes.map(&:id)
      history = History.new(changes: version.library_changes.includes(:dependency_links).ordered)
      if changes.any? { |change| history.dependent_changes(change, active_only: true).any? { |dependent| !ids.include?(dependent.id) } }
        raise InvalidUndo, "This edit is blocked by later dependent edits."
      end
      changes.each { |change| verify_applied!(change) }
    end

    def self.verify_applied!(change)
      details = change.details
      folders = change.library_version.library_folders
      placements = change.library_version.library_folder_contents
      valid = case change.action_type
      when "add_folder"
        folders.exists?(id: details["folder_id"], parent_folder_id: details["parent_folder_id"], logo_id: details["logo_id"])
      when "move_folder"
        folders.exists?(id: details["folder_id"], parent_folder_id: details["destination_folder_id"], logo_id: nil)
      when "add_content", "duplicate_content"
        placements.exists?(id: details["placement_id"], library_folder_id: details["folder_id"], content_id: details["content_id"])
      when "move_content"
        !placements.exists?(library_folder_id: details["source_folder_id"], content_id: details["content_id"]) &&
          placements.exists?(id: details["destination_placement_id"], library_folder_id: details["destination_folder_id"], content_id: details["content_id"])
      when "remove_content"
        !placements.exists?(library_folder_id: details["folder_id"], content_id: details["content_id"])
      when "remove_folder"
        !folders.exists?(id: details["folder_ids"]) && !placements.exists?(id: details["placement_ids"])
      when "duplicate_folder"
        folders.where(id: details["folder_ids"]).count == Array(details["folder_ids"]).length &&
          placements.where(id: details["placement_ids"]).count == Array(details["placement_ids"]).length
      else
        false
      end
      raise InvalidUndo, "This edit is blocked because its folders or content have changed." unless valid
    end
  end
end
