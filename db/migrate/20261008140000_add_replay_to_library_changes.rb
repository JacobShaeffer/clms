class AddReplayToLibraryChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :library_changes, :replay_snapshot, :jsonb
    add_column :library_changes, :undo_group_key, :string
    add_reference :library_changes, :redo_of, foreign_key: { to_table: :library_changes }, index: { unique: true }
    add_index :library_changes, [ :library_version_id, :undo_group_key ]
  end
end
