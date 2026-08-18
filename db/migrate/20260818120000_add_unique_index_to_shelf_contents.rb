class AddUniqueIndexToShelfContents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      DELETE FROM shelf_contents
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM shelf_contents
        GROUP BY shelf_id, content_id
      )
    SQL

    add_index :shelf_contents,
      [ :shelf_id, :content_id ],
      unique: true,
      name: :index_shelf_contents_on_shelf_id_and_content_id
  end

  def down
    remove_index :shelf_contents, name: :index_shelf_contents_on_shelf_id_and_content_id
  end
end
