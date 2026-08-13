class CreateActiveShelves < ActiveRecord::Migration[8.1]
  def change
    create_table :active_shelves do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shelf, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :active_shelves, [ :user_id, :shelf_id ], unique: true
    add_index :active_shelves, [ :user_id, :position ], unique: true
  end
end
