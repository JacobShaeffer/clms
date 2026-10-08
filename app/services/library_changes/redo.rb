module LibraryChanges
  class Redo
    def self.group(change)
      return [] unless change.undone? && change.undo_group_key.present?

      change.library_version.library_changes.where(undo_group_key: change.undo_group_key).order(:id).to_a
    end

    def self.call(change:, user:, confirmed_change_ids:, confirmed_undo_group_key: change.undo_group_key)
      library = change.library_version.library
      library.with_lock do
        change.reload
        changes = group(change)
        confirmed = Array(confirmed_change_ids).map { |id| Integer(id, exception: false) }
        unless confirmed_undo_group_key.present? && confirmed_undo_group_key == change.undo_group_key &&
            confirmed.all? && confirmed.uniq.sort == changes.map(&:id).sort
          raise InvalidUndo, "The edits to redo have changed. Open the change again to review them."
        end
        validate!(changes:, user:, library:)
        changes.each do |record|
          ReplaySnapshot.apply!(record.replay_snapshot)
          record.mark_redone!
        end
        changes
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordNotFound,
        ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotUnique
      raise InvalidUndo, "This redo is blocked because required library data has changed."
    end

    def self.validate!(changes:, user:, library:)
      raise InvalidUndo, "This change has no saved redo data." if changes.empty?
      unless changes.all? { |record| LibraryChangePolicy.new(user, record).redo? }
        raise InvalidUndo, "You cannot redo these library changes."
      end
      version = changes.first.library_version
      unless library.current_version_id == version.id && version.reload.editable?
        raise InvalidUndo, "Only changes in the editable current version can be redone."
      end
      ids = changes.map(&:id)
      snapshots = changes.filter_map(&:replay_snapshot)
      content_ids = snapshots.flat_map { |snapshot| snapshot["applied"]["placements"].values.compact.map { |row| row["content_id"] } }.uniq
      logo_ids = snapshots.flat_map { |snapshot| snapshot["applied"]["folders"].values.compact.filter_map { |row| row["logo_id"] } }.uniq
      unless Content.where(id: content_ids).count == content_ids.length && LibraryAsset.where(id: logo_ids).count == logo_ids.length
        raise InvalidUndo, "Required content or library assets are no longer available."
      end
      current = ReplaySnapshot.world(version)
      changes.each do |record|
        unless record.undone? && record.replay_snapshot.present? && record.redo_change.nil?
          raise InvalidUndo, "This change has no available redo or has already been redone."
        end
        record.prerequisites.each do |prerequisite|
          next if ids.include?(prerequisite.id) || active_replacement(prerequisite)

          raise InvalidUndo, "Redo the required earlier edits first."
        end
        ReplaySnapshot.simulate!(record.replay_snapshot, current)
      end
    end

    def self.active_replacement(change)
      change = change.redo_change while change&.undone? && change.redo_change
      change unless change&.undone?
    end
  end
end
