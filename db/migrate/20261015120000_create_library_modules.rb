class CreateLibraryModules < ActiveRecord::Migration[8.1]
  def change
    create_table :library_modules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :folder_name, null: false
      t.references :icon, null: false, foreign_key: { to_table: :library_assets }
      t.timestamps
    end
  end
end
