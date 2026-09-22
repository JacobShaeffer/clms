class LibraryChangeTarget < ApplicationRecord
  TARGET_KINDS = { folder: "folder", content: "content" }.freeze
  EFFECTS = { new: "new", moved: "moved", removed: "removed" }.freeze

  belongs_to :library_change

  enum :target_kind, TARGET_KINDS, validate: true
  enum :effect, EFFECTS, prefix: true, validate: true

  validates :resource_key, :label, presence: true
  validates :target_id, :folder_id, numericality: { only_integer: true, greater_than: 0 }
  validates :content_id,
    numericality: { only_integer: true, greater_than: 0 },
    if: :content?
  validates :content_id, absence: true, if: :folder?
  validates :resource_key, uniqueness: { scope: :library_change_id }
  validate :change_accepts_targets, on: :create

  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def change_accepts_targets
    return if library_change.blank?
    return if library_change.pending? && library_change.library_version.editable?

    errors.add(:library_change, "must be pending in an editable version")
  end

  def prevent_mutation
    errors.add(:base, "Library change targets cannot be modified")
    throw :abort
  end
end
