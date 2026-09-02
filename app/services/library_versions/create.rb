module LibraryVersions
  class Create
    def self.call(library:, version_number:, user:)
      new(library:, version_number:, user:).call
    end

    def initialize(library:, version_number:, user:)
      @library = library
      @version_number = version_number
      @user = user
    end

    def call
      library.with_lock do
        previous_version = library.current_version
        new_version = library.library_versions.build(
          version_number:,
          user:,
          previous_version:
        )

        validate_new_version!(new_version, previous_version)
        finalize_content_manifest!(previous_version) if previous_version
        previous_version&.update!(locked_at: Time.current)
        new_version.save!

        clone_content_manifest!(previous_version, new_version) if previous_version
        folder_ids = clone_folders!(previous_version, new_version) if previous_version
        clone_placements!(previous_version, new_version, folder_ids) if previous_version

        library.update!(current_version: new_version)
        new_version
      end
    end

    private

    attr_reader :library, :version_number, :user

    def validate_new_version!(new_version, previous_version)
      unless previous_version.nil? || previous_version.editable?
        new_version.errors.add(:base, "Current library version is locked")
        raise ActiveRecord::RecordInvalid, new_version
      end

      raise ActiveRecord::RecordInvalid, new_version unless new_version.valid?
    end

    def finalize_content_manifest!(version)
      placed_content_ids = version.library_folder_contents.distinct.pluck(:content_id)
      orphaned_manifests = version.library_version_contents
      orphaned_manifests = orphaned_manifests.where.not(content_id: placed_content_ids) if placed_content_ids.any?
      orphaned_manifests.destroy_all

      Content.where(id: placed_content_ids).with_attached_file.find_each do |content|
        manifest = version.library_version_contents.find_or_initialize_by(content:)
        manifest.file_checksum = content.file.attached? ? content.file.blob.checksum : nil
        manifest.save!
      end
    end

    def clone_content_manifest!(source, destination)
      rows = source.library_version_contents.pluck(:content_id, :file_checksum).map do |content_id, file_checksum|
        {
          library_version_id: destination.id,
          content_id:,
          file_checksum:
        }
      end
      destination.library_version_contents.insert_all!(rows) if rows.any?
    end

    def clone_folders!(source, destination)
      folder_ids = {}
      pending = source.library_folders.order(:id).to_a

      until pending.empty?
        ready, pending = pending.partition do |folder|
          folder.parent_folder_id.nil? || folder_ids.key?(folder.parent_folder_id)
        end
        raise_invalid_folder_tree!(source) if ready.empty?

        ready.each do |folder|
          copy = destination.library_folders.create!(
            library: destination.library,
            parent_folder_id: folder_ids[folder.parent_folder_id],
            name: folder.name,
            user_id: folder.user_id,
            logo_id: folder.logo_id
          )
          folder_ids[folder.id] = copy.id
        end
      end

      folder_ids
    end

    def clone_placements!(source, destination, folder_ids)
      source.library_folder_contents.find_in_batches do |placements|
        rows = placements.map do |placement|
          {
            library_folder_id: folder_ids.fetch(placement.library_folder_id),
            content_id: placement.content_id,
            library_version_id: destination.id
          }
        end
        LibraryFolderContent.insert_all!(rows) if rows.any?
      end
    end

    def raise_invalid_folder_tree!(version)
      version.errors.add(:library_folders, "contain an invalid parent hierarchy")
      raise ActiveRecord::RecordInvalid, version
    end
  end
end
