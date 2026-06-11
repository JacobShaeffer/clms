class CreateContents < ActiveRecord::Migration[8.1]
  def change
    create_table :contents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.string :display_title
      t.text :description
      t.integer :year_of_publication
      t.integer :additional_notes

      t.timestamps
    end
  end
end
