class CreateContentTablePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :content_table_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :table_key, null: false
      t.jsonb :state, null: false, default: {}

      t.timestamps
    end

    add_index :content_table_preferences, [ :user_id, :table_key ], unique: true
  end
end
