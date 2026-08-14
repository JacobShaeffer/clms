class RenameCartsToShelves < ActiveRecord::Migration[8.1]
  def change
    rename_table :carts, :shelves
    rename_table :cart_contents, :shelf_contents
    rename_column :shelf_contents, :cart_id, :shelf_id
  end
end
