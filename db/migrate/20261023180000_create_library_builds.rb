class CreateLibraryBuilds < ActiveRecord::Migration[8.1]
  def change
    create_table :library_builds do |t|
      t.references :library_version, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.integer :generation, null: false, default: 1
      t.integer :published_generation
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :published_at
      t.text :last_error
      t.timestamps
      t.index [ :status, :requested_at ]
      t.check_constraint "status IN ('queued', 'exporting', 'ready', 'failed')", name: "library_builds_status"
      t.check_constraint "generation > 0 AND (published_generation IS NULL OR (published_generation > 0 AND published_generation <= generation))", name: "library_builds_generations"
    end
  end
end
