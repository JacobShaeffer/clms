class RemoveUnusedRedoLinks < ActiveRecord::Migration[8.1]
  def up
    if select_value(<<~SQL)
      SELECT EXISTS (
        SELECT 1 FROM library_change_dependencies
        WHERE prerequisite_change_id IN (
          SELECT redo_of_id FROM library_changes WHERE redo_of_id IS NOT NULL
        )
      )
    SQL
      raise ActiveRecord::MigrationError, "Resolve dependencies on superseded redo records before removing redo_of_id."
    end

    # Keep the original and replacement audit entries. Superseded entries already
    # had no available redo, so discard only their obsolete replay data.
    execute <<~SQL
      UPDATE library_changes SET replay_snapshot = NULL, undo_group_key = NULL
      WHERE id IN (SELECT redo_of_id FROM library_changes WHERE redo_of_id IS NOT NULL)
    SQL

    remove_reference :library_changes, :redo_of, foreign_key: { to_table: :library_changes }
  end

  def down
    add_reference :library_changes, :redo_of, foreign_key: { to_table: :library_changes }, index: { unique: true }
  end
end
