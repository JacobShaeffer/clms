class AddVersionedLibrarySnapshots < ActiveRecord::Migration[8.1]
  def up
    add_column :library_versions, :locked_at, :datetime

    ensure_every_library_has_a_current_version
    lock_non_current_versions

    add_index :library_versions,
      :library_id,
      unique: true,
      where: "locked_at IS NULL",
      name: "index_library_versions_on_one_unlocked_per_library"
    add_index :library_versions,
      [ :id, :library_id ],
      unique: true,
      name: "index_library_versions_on_id_and_library_id"

    add_reference :library_folders, :library_version, null: true, foreign_key: true
    execute <<~SQL.squish
      UPDATE library_folders
      SET library_version_id = libraries.current_version_id
      FROM libraries
      WHERE libraries.id = library_folders.library_id
    SQL
    change_column_null :library_folders, :library_version_id, false

    add_reference :library_folder_contents, :library_version, null: true, foreign_key: true
    execute <<~SQL.squish
      UPDATE library_folder_contents
      SET library_version_id = library_folders.library_version_id
      FROM library_folders
      WHERE library_folders.id = library_folder_contents.library_folder_id
    SQL
    change_column_null :library_folder_contents, :library_version_id, false

    create_table :library_version_contents do |t|
      t.references :library_version, null: false, foreign_key: true
      t.references :content, null: false, foreign_key: true
      t.string :file_checksum

      t.timestamps
    end
    add_index :library_version_contents,
      [ :library_version_id, :content_id ],
      unique: true,
      name: "index_library_version_contents_on_version_and_content"

    backfill_content_manifests
    add_integrity_constraints
  end

  def down
    remove_foreign_key :library_folder_contents, name: "fk_folder_contents_manifest"
    remove_foreign_key :library_folder_contents, name: "fk_folder_contents_folder_version"
    remove_foreign_key :library_folders, name: "fk_library_folders_parent_version"
    remove_foreign_key :library_folders, name: "fk_library_folders_version_library"
    remove_foreign_key :libraries, name: "fk_libraries_current_version_library"

    drop_table :library_version_contents
    remove_reference :library_folder_contents, :library_version, foreign_key: true
    remove_reference :library_folders, :library_version, foreign_key: true

    remove_index :library_versions, name: "index_library_versions_on_id_and_library_id"
    remove_index :library_versions, name: "index_library_versions_on_one_unlocked_per_library"
    remove_column :library_versions, :locked_at
  end

  private

  def ensure_every_library_has_a_current_version
    execute <<~SQL.squish
      UPDATE libraries
      SET current_version_id = latest_versions.id
      FROM (
        SELECT DISTINCT ON (library_id) id, library_id
        FROM library_versions
        ORDER BY library_id, created_at DESC, id DESC
      ) AS latest_versions
      WHERE libraries.current_version_id IS NULL
        AND latest_versions.library_id = libraries.id
    SQL

    execute <<~SQL.squish
      INSERT INTO library_versions
        (library_id, user_id, version_number, created_at, updated_at)
      SELECT libraries.id, libraries.user_id, '1.0', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM libraries
      WHERE libraries.current_version_id IS NULL
        AND NOT EXISTS (
          SELECT 1
          FROM library_versions
          WHERE library_versions.library_id = libraries.id
        )
    SQL

    execute <<~SQL.squish
      UPDATE libraries
      SET current_version_id = initial_versions.id
      FROM library_versions AS initial_versions
      WHERE libraries.current_version_id IS NULL
        AND initial_versions.library_id = libraries.id
        AND initial_versions.version_number = '1.0'
    SQL
  end

  def lock_non_current_versions
    execute <<~SQL.squish
      UPDATE library_versions
      SET locked_at = COALESCE(library_versions.updated_at, CURRENT_TIMESTAMP)
      FROM libraries
      WHERE libraries.id = library_versions.library_id
        AND libraries.current_version_id <> library_versions.id
    SQL
  end

  def backfill_content_manifests
    execute <<~SQL.squish
      INSERT INTO library_version_contents
        (library_version_id, content_id, file_checksum, created_at, updated_at)
      SELECT DISTINCT
        library_folder_contents.library_version_id,
        library_folder_contents.content_id,
        active_storage_blobs.checksum,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM library_folder_contents
      LEFT JOIN active_storage_attachments
        ON active_storage_attachments.record_type = 'Content'
        AND active_storage_attachments.record_id = library_folder_contents.content_id
        AND active_storage_attachments.name = 'file'
      LEFT JOIN active_storage_blobs
        ON active_storage_blobs.id = active_storage_attachments.blob_id
    SQL
  end

  def add_integrity_constraints
    add_foreign_key :libraries,
      :library_versions,
      column: [ :current_version_id, :id ],
      primary_key: [ :id, :library_id ],
      name: "fk_libraries_current_version_library"

    add_foreign_key :library_folders,
      :library_versions,
      column: [ :library_version_id, :library_id ],
      primary_key: [ :id, :library_id ],
      name: "fk_library_folders_version_library"

    add_index :library_folders,
      [ :id, :library_version_id ],
      unique: true,
      name: "index_library_folders_on_id_and_library_version_id"
    add_foreign_key :library_folders,
      :library_folders,
      column: [ :parent_folder_id, :library_version_id ],
      primary_key: [ :id, :library_version_id ],
      name: "fk_library_folders_parent_version"

    add_foreign_key :library_folder_contents,
      :library_folders,
      column: [ :library_folder_id, :library_version_id ],
      primary_key: [ :id, :library_version_id ],
      name: "fk_folder_contents_folder_version"
    add_foreign_key :library_folder_contents,
      :library_version_contents,
      column: [ :library_version_id, :content_id ],
      primary_key: [ :library_version_id, :content_id ],
      name: "fk_folder_contents_manifest"
  end
end
