class CreateContentsMetadata < ActiveRecord::Migration[8.1]
  def change
    create_table :contents_metadata do |t|
      t.references :metadata, null: false, foreign_key: true
      t.references :content, null: false, foreign_key: true

      t.timestamps
    end
  end
end
