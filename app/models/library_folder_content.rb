class LibraryFolderContent < ApplicationRecord
  belongs_to :library_folder
  belongs_to :content
  belongs_to :library_version, inverse_of: :library_folder_contents
  belongs_to :pending_removal_change,
    class_name: "LibraryChange",
    inverse_of: :pending_removed_placements,
    optional: true

  scope :active, -> { where(pending_removal_change_id: nil) }

  validates :content_id, uniqueness: { scope: :library_folder_id }
  validate :library_version_matches_folder
  validate :library_folder_is_active, on: :create
  validate :placement_identity_is_unchanged, on: :update
  validate :library_version_is_editable
  validate :pending_removal_matches_version
  validate :pending_removed_record_is_read_only, on: :update

  before_validation :assign_library_version
  before_create :ensure_content_manifest
  before_destroy :prevent_locked_version_destruction, prepend: true
  before_destroy :prevent_unapproved_pending_removal, prepend: true
  after_destroy :remove_unused_content_manifest

  def pending_removal?
    pending_removal_change_id.present?
  end

  def destroy_for_approved_removal!
    @approved_removal = true
    destroy!
  ensure
    @approved_removal = false unless destroyed?
  end

  private

  def assign_library_version
    self.library_version ||= library_folder&.library_version
  end

  def library_version_matches_folder
    return if library_folder.blank? || library_version.blank?
    return if library_folder.library_version_id == library_version_id

    errors.add(:library_version, "must match the folder's library version")
  end

  def library_folder_is_active
    return if library_folder_id.blank?
    return if LibraryFolder.where(id: library_folder_id, pending_removal_change_id: nil).exists?

    errors.add(:library_folder, "cannot be pending removal")
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

  def prevent_unapproved_pending_removal
    return if pending_removal_change_id_in_database.blank? || @approved_removal

    errors.add(:base, "Content pending removal can only be deleted by approval")
    throw :abort
  end

  def remove_unused_content_manifest
    return if library_version.library_folder_contents.exists?(content_id:)

    library_version.library_version_contents.find_by(content_id:)&.destroy!
  end

  def pending_removal_matches_version
    return if pending_removal_change.blank?
    return if pending_removal_change.library_version_id == library_version_id &&
      pending_removal_change.pending? &&
      (pending_removal_change.remove_folder? || pending_removal_change.remove_content?)

    errors.add(:pending_removal_change, "must be a pending removal in the same version")
  end

  def pending_removed_record_is_read_only
    return if pending_removal_change_id_in_database.blank?
    return unless has_changes_to_save?

    errors.add(:base, "Content pending removal cannot be changed")
  end
end
