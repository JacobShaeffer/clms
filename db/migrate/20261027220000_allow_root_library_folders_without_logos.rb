class AllowRootLibraryFoldersWithoutLogos < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :library_folders,
      "(parent_folder_id IS NULL AND logo_id IS NOT NULL) OR (parent_folder_id IS NOT NULL AND logo_id IS NULL)",
      name: "library_folders_root_only_logo"
    add_check_constraint :library_folders,
      "parent_folder_id IS NULL OR logo_id IS NULL",
      name: "library_folders_root_only_logo"
  end
end
