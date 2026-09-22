class TightenLibraryChangeTargets < ActiveRecord::Migration[8.1]
  def change
    change_column_null :library_change_targets, :target_id, false
    change_column_null :library_change_targets, :folder_id, false
    add_index :library_change_targets, :folder_id
    add_check_constraint :library_change_targets,
      "(target_kind = 'folder' AND content_id IS NULL) OR " \
        "(target_kind = 'content' AND content_id IS NOT NULL)",
      name: "library_change_targets_identifier_shape"
  end
end
