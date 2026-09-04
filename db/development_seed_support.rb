module DevelopmentSeedSupport
  module_function

  def reset_data!
    purge_active_storage!

    ActiveShelf.delete_all
    ContentTablePreference.delete_all
    LibraryFolderContent.delete_all
    LibraryVersionContent.delete_all
    ShelfContent.delete_all
    ContentMetadatum.delete_all
    Library.update_all(current_version_id: nil)
    LibraryFolder.delete_all
    LibraryVersion.delete_all
    Library.delete_all
    Shelf.delete_all
    Content.delete_all
    Metadatum.delete_all
    MetadataType.delete_all
    LibraryAsset.delete_all
    User.delete_all
  end

  def create_users!
    User::ROLES.keys.map(&:to_s).index_with do |role|
      User.create!(
        name: role,
        email: "#{role}@#{role}.com",
        password: "#{role}#{role}",
        password_confirmation: "#{role}#{role}",
        role:
      )
    end
  end

  def purge_active_storage!
    ActiveStorage::Blob.find_each(&:delete)
    ActiveStorage::Attachment.delete_all
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Blob.delete_all
  end
end
