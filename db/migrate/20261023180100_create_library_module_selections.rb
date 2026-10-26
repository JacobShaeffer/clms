class CreateLibraryModuleSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :library_module_selections do |t|
      t.references :library, null: false, foreign_key: true
      t.references :library_module, null: false, foreign_key: true
      t.timestamps
      t.index [ :library_id, :library_module_id ], unique: true
    end
  end
end
