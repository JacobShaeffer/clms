class AddAssetTypeToLibraryAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :library_assets, :asset_type, :string
  end
end
