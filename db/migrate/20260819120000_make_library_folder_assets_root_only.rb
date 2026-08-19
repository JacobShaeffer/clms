class MakeLibraryFolderAssetsRootOnly < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME = "library_folders_root_only_logo"

  def up
    execute <<~SQL.squish
      UPDATE library_folders
      SET logo_id = NULL
      WHERE parent_folder_id IS NOT NULL
    SQL

    change_column_null :library_folders, :logo_id, true
    add_check_constraint :library_folders,
      <<~SQL.squish,
        (parent_folder_id IS NULL AND logo_id IS NOT NULL)
        OR (parent_folder_id IS NOT NULL AND logo_id IS NULL)
      SQL
      name: CONSTRAINT_NAME
  end

  def down
    remove_check_constraint :library_folders, name: CONSTRAINT_NAME

    execute <<~SQL.squish
      UPDATE library_folders AS child
      SET logo_id = (
        WITH RECURSIVE ancestors(id, parent_folder_id, logo_id) AS (
          SELECT parent.id, parent.parent_folder_id, parent.logo_id
          FROM library_folders AS parent
          WHERE parent.id = child.parent_folder_id

          UNION ALL

          SELECT parent.id, parent.parent_folder_id, parent.logo_id
          FROM library_folders AS parent
          JOIN ancestors ON parent.id = ancestors.parent_folder_id
        )
        SELECT logo_id
        FROM ancestors
        WHERE parent_folder_id IS NULL
        LIMIT 1
      )
      WHERE child.parent_folder_id IS NOT NULL
    SQL

    change_column_null :library_folders, :logo_id, false
  end
end
