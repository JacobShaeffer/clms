class RenameLibraryAssetDesignDocumentsAttachment < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE active_storage_attachments
      SET name = 'design_files'
      WHERE record_type = 'LibraryAsset'
        AND name = 'design_documents'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE active_storage_attachments
      SET name = 'design_documents'
      WHERE record_type = 'LibraryAsset'
        AND name = 'design_files'
    SQL
  end
end
