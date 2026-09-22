class LibraryFolder < ApplicationRecord
  belongs_to :library, inverse_of: :library_folders
  belongs_to :library_version, inverse_of: :library_folders
  belongs_to :parent_folder, class_name: "LibraryFolder", optional: true
  belongs_to :user
  belongs_to :logo, class_name: "LibraryAsset", optional: true
  belongs_to :pending_removal_change,
    class_name: "LibraryChange",
    inverse_of: :pending_removed_folders,
    optional: true

  has_many :child_folders,
    class_name: "LibraryFolder",
    foreign_key: :parent_folder_id,
    inverse_of: :parent_folder,
    dependent: :restrict_with_error
  has_many :library_folder_contents, dependent: :restrict_with_error
  has_many :contents, through: :library_folder_contents

  scope :roots, -> { where(parent_folder_id: nil) }
  scope :active, -> { where(pending_removal_change_id: nil) }

  validates :name, presence: true
  validates :logo, presence: true, if: :root_folder?
  validates :logo, absence: true, unless: :root_folder?
  validate :parent_folder_belongs_to_library
  validate :parent_folder_belongs_to_version
  validate :library_version_belongs_to_library
  validate :library_version_is_unchanged, on: :update
  validate :library_version_is_editable
  validate :parent_folder_is_not_self
  validate :parent_folder_is_not_descendant
  validate :parent_folder_is_active
  validate :pending_removal_matches_version
  validate :pending_removed_record_is_read_only, on: :update

  before_validation :assign_snapshot_ownership
  before_destroy :prevent_locked_version_destruction, prepend: true
  before_destroy :prevent_unapproved_pending_removal, prepend: true

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

  def assign_snapshot_ownership
    self.library ||= library_version&.library
    self.library_version ||= library&.current_version
  end

  def root_folder?
    parent_folder.nil?
  end

  def parent_folder_belongs_to_library
    return if parent_folder.blank? || parent_folder.library_id == library_id

    errors.add(:parent_folder, "must belong to this library")
  end

  def parent_folder_belongs_to_version
    return if parent_folder.blank? || parent_folder.library_version_id == library_version_id

    errors.add(:parent_folder, "must belong to the same library version")
  end

  def library_version_belongs_to_library
    return if library_version.blank? || library.blank? || library_version.library_id == library_id

    errors.add(:library_version, "must belong to this library")
  end

  def library_version_is_unchanged
    return unless will_save_change_to_library_version_id?

    errors.add(:library_version, "cannot be changed")
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

  def prevent_locked_version_destruction
    return unless (persisted_library_version || library_version)&.locked?

    errors.add(:base, "Locked library versions cannot be changed")
    throw :abort
  end

  def prevent_unapproved_pending_removal
    return if pending_removal_change_id_in_database.blank? || @approved_removal

    errors.add(:base, "Folders pending removal can only be deleted by approval")
    throw :abort
  end

  def pending_removal_matches_version
    return if pending_removal_change.blank?
    return if pending_removal_change.library_version_id == library_version_id &&
      pending_removal_change.pending? && pending_removal_change.remove_folder?

    errors.add(:pending_removal_change, "must be a pending folder removal in the same version")
  end

  def pending_removed_record_is_read_only
    return if pending_removal_change_id_in_database.blank?
    return unless has_changes_to_save?

    errors.add(:base, "Folders pending removal cannot be changed")
  end

  def parent_folder_is_active
    return if parent_folder_id.blank?
    return if self.class.where(id: parent_folder_id, pending_removal_change_id: nil).exists?

    errors.add(:parent_folder, "cannot be pending removal")
  end

  def parent_folder_is_not_self
    return if parent_folder_id.blank? || parent_folder_id != id

    errors.add(:parent_folder, "cannot be itself")
  end

  def parent_folder_is_not_descendant
    current_folder = parent_folder
    visited_ids = {}

    while current_folder
      return errors.add(:parent_folder, "cannot be a descendant") if current_folder == self
      break if current_folder.id.present? && visited_ids[current_folder.id]

      visited_ids[current_folder.id] = true if current_folder.id.present?
      current_folder = current_folder.parent_folder
    end
  end
end
