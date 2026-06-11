class CreateMetadata < ActiveRecord::Migration[8.1]
  def change
    create_table :metadata do |t|
      t.references :user, null: false, foreign_key: true
      t.references :metadata_type, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :under_review, default: true

      t.timestamps
    end
  end
end
