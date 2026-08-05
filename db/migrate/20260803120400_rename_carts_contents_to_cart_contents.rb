class RenameCartsContentsToCartContents < ActiveRecord::Migration[8.1]
  def change
    rename_table :carts_contents, :cart_contents
  end
end
