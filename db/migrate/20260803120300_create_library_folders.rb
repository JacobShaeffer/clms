class CreateLibraryFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :library_folders do |t|
      t.references :library, null: false, foreign_key: true
      t.references :parent_folder, null: true, foreign_key: { to_table: :library_folders }
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.references :logo, null: false, foreign_key: { to_table: :library_assets }

      t.timestamps
    end
  end
end
