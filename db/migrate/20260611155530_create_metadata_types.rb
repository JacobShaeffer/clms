class CreateMetadataTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :metadata_types do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.integer :order, default: 0
      t.integer :access_level, default: 0

      t.timestamps
    end
  end
end
