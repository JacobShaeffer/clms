class CreateCartsContents < ActiveRecord::Migration[8.1]
  def change
    create_table :carts_contents do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :content, null: false, foreign_key: true

      t.timestamps
    end
  end
end
