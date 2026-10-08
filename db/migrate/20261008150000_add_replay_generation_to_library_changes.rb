class AddReplayGenerationToLibraryChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :library_changes, :replay_generation, :integer, null: false, default: 0
  end
end
