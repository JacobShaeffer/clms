class AddTrashFieldsToContents < ActiveRecord::Migration[8.1]
  def change
    add_column :contents, :trashed_at, :datetime
    add_column :contents, :trash_comment, :text
    add_index :contents, :trashed_at
  end
end
