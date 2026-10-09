module LibraryChanges
  class CascadeUndo
    def self.call(change:, user:, confirmed_dependent_ids:)
      library = change.library_version.library
      Undo.with_transaction(library:) do
        change.reload
        history = History.new(changes: change.library_version.library_changes
          .includes(:dependency_links).ordered)
        dependents = history.dependent_changes(change, active_only: true)
        confirmed_ids = Array(confirmed_dependent_ids).map { |id| Integer(id, exception: false) }
        unless confirmed_ids.all? && confirmed_ids.uniq.sort == dependents.map(&:id).sort
          raise InvalidUndo, "Dependent edits have changed. Open the change again to review them before undoing."
        end

        changes = [ change, *dependents ]
        unless changes.all? { |record| LibraryChangePolicy.new(user, record).undo? }
          raise InvalidUndo, "Only an admin can undo a chain that includes another person's edits."
        end
        raise InvalidUndo, "This library change has already been undone." if change.undone?

        undo_group_key = SecureRandom.uuid
        changes.sort_by(&:id).reverse_each { |record| Undo.call(change: record, user:, undo_group_key:) }
      end
      change
    end
  end
end
