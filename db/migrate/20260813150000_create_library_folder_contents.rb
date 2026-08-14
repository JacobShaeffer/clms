class CreateLibraryFolderContents < ActiveRecord::Migration[8.1]
  def change
    create_table :library_folder_contents do |t|
      t.references :library_folder, null: false, foreign_key: true
      t.references :content, null: false, foreign_key: true

      t.timestamps
    end

    add_index :library_folder_contents,
      [ :library_folder_id, :content_id ],
      unique: true
  end
end
