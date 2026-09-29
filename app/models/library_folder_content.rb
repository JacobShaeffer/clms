class LibraryFolderContent < ApplicationRecord
  belongs_to :library_folder
  belongs_to :content
  belongs_to :library_version, inverse_of: :library_folder_contents

  validates :content_id, uniqueness: { scope: :library_folder_id }
  validate :library_version_matches_folder
  validate :placement_identity_is_unchanged, on: :update
  validate :library_version_is_editable

  before_validation :assign_library_version
  before_create :ensure_content_manifest
  before_destroy :prevent_locked_version_destruction, prepend: true
  after_destroy :remove_unused_content_manifest

  private

  def assign_library_version
    self.library_version ||= library_folder&.library_version
  end

  def library_version_matches_folder
    return if library_folder.blank? || library_version.blank?
    return if library_folder.library_version_id == library_version_id

    errors.add(:library_version, "must match the folder's library version")
  end

  def placement_identity_is_unchanged
    identity_changed = will_save_change_to_library_folder_id? ||
      will_save_change_to_content_id? ||
      will_save_change_to_library_version_id?
    return unless identity_changed

    errors.add(:base, "Content placements cannot be reassigned")
  end

  def library_version_is_editable
    version = persisted_library_version || library_version
    return if version.blank? || version.editable?

    errors.add(:base, "Locked library versions cannot be changed")
  end

  def persisted_library_version
    version_id = persisted? ? library_version_id_in_database : library_version_id
    return unless version_id

    LibraryVersion.find_by(id: version_id)
  end

  def ensure_content_manifest
    library_version.ensure_content_manifest!(content)
  end

  def prevent_locked_version_destruction
    return unless (persisted_library_version || library_version)&.locked?

    errors.add(:base, "Locked library versions cannot be changed")
    throw :abort
  end

  def remove_unused_content_manifest
    return if library_version.library_folder_contents.exists?(content_id:)

    library_version.library_version_contents.find_by(content_id:)&.destroy!
  end
end
