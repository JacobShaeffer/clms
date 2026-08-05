class AddCurrentVersionToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_reference :libraries,
      :current_version,
      null: true,
      foreign_key: { to_table: :library_versions },
      index: { unique: true }
  end
end
