class CreateLibraryAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :library_assets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :language

      t.timestamps
    end
  end
end
