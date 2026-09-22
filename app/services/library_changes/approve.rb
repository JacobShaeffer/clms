module LibraryChanges
  class Approve
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
        blocker = change.approval_blocker
        if blocker
          raise InvalidResolution,
            "Approve #{blocker.display_label} before approving this change."
        end

        finalize_removal!
        change.update!(status: :approved, resolved_by: user, resolved_at: Time.current)
      end
      change
    end

    private

    attr_reader :change, :user

    def ensure_resolvable!(library)
      raise InvalidResolution, "Only admins can approve library changes." unless user&.admin?
      raise InvalidResolution, "This change has already been resolved." unless change.pending?
      unless library.current_version_id == change.library_version_id && change.library_version.editable?
        raise InvalidResolution, "Only changes in the editable current version can be approved."
      end
    end

    def finalize_removal!
      if change.remove_content?
        finalize_content_removal!
      elsif change.remove_folder?
        finalize_folder_removal!
      end
    end

    def finalize_content_removal!
      placement = LibraryFolderContent.find_by(
        id: detail("placement_id"),
        pending_removal_change_id: change.id
      )
      placement&.destroy_for_approved_removal!
    end

    def finalize_folder_removal!
      placement_ids = Array(detail("placement_ids"))
      LibraryFolderContent.where(id: placement_ids).find_each do |placement|
        placement.destroy_for_approved_removal!
      end
      Array(detail("folder_ids")).reverse_each do |folder_id|
        LibraryFolder.find_by(id: folder_id)&.destroy_for_approved_removal!
      end
      LibraryFolderOperations::Remove.remove_unused_manifests(
        library_version: change.library_version,
        content_ids: Array(detail("content_ids"))
      )
    end

    def detail(key)
      change.details.fetch(key)
    end
  end
end
