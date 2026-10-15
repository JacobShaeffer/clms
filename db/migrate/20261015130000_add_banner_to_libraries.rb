class AddBannerToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_reference :libraries, :banner, foreign_key: { to_table: :library_assets }
  end
end
