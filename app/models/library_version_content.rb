class LibraryVersionContent < ApplicationRecord
  belongs_to :library_version, inverse_of: :library_version_contents
  belongs_to :content, inverse_of: :library_version_contents

  validates :content_id, uniqueness: { scope: :library_version_id }
  validate :snapshot_identity_is_unchanged, on: :update
  validate :library_version_is_editable

  before_destroy :prevent_locked_version_destruction, prepend: true

  private

  def snapshot_identity_is_unchanged
    return unless will_save_change_to_library_version_id? || will_save_change_to_content_id?

    errors.add(:base, "A content manifest cannot be moved to another snapshot")
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
end
