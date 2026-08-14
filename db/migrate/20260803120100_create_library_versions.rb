class CreateLibraryVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :library_versions do |t|
      t.references :library, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :version_number, null: false
      t.references :previous_version,
        null: true,
        foreign_key: { to_table: :library_versions },
        index: { unique: true }

      t.timestamps
    end

    add_index :library_versions, [ :library_id, :version_number ], unique: true
  end
end
