class LibraryChange < ApplicationRecord
  ACTION_TYPES = {
    add_folder: "add_folder",
    add_content: "add_content",
    move_folder: "move_folder",
    move_content: "move_content",
    remove_folder: "remove_folder",
    remove_content: "remove_content",
    duplicate_folder: "duplicate_folder",
    duplicate_content: "duplicate_content"
  }.freeze
  belongs_to :library_version
  belongs_to :user
  belongs_to :undone_by, class_name: "User", optional: true

  has_many :library_change_targets, dependent: :restrict_with_error
  has_many :dependency_links,
    class_name: "LibraryChangeDependency",
    dependent: :restrict_with_error,
    inverse_of: :library_change
  has_many :prerequisites, through: :dependency_links, source: :prerequisite_change
  has_many :dependent_links,
    class_name: "LibraryChangeDependency",
    foreign_key: :prerequisite_change_id,
    dependent: :restrict_with_error,
    inverse_of: :prerequisite_change
  has_many :dependents, through: :dependent_links, source: :library_change
  enum :action_type, ACTION_TYPES, validate: true

  validates :batch_key, presence: true
  validates :details, presence: true
  validate :undo_state_is_complete
  validate :audit_record_changes_only_when_undone, on: :update
  validate :library_version_is_editable, on: %i[create update]

  before_destroy :prevent_destruction, prepend: true

  scope :ordered, -> { order(:created_at, :id) }
  scope :not_undone, -> { where(undone_at: nil) }

  def undo_blocker
    dependents.not_undone.ordered.first
  end

  def undoable?
    !undone? && undo_blocker.nil?
  end

  def undone?
    undone_at.present?
  end

  def direct_target
    library_change_targets.find(&:direct?)
  end

  def display_label
    direct_target&.label || action_type.humanize
  end

  private

  def undo_state_is_complete
    return if undone_at.present? == undone_by.present?

    errors.add(:base, "Undo time and user must both be present or both be blank")
  end

  def audit_record_changes_only_when_undone
    changed_attributes = changes_to_save.keys
    return if changed_attributes.empty?

    if undone_at_in_database.present?
      errors.add(:base, "Undone library changes cannot be modified")
      return
    end
    return if (changed_attributes - %w[undone_at undone_by_id]).empty?

    errors.add(:base, "Library change audit records can only be marked undone")
  end

  def library_version_is_editable
    return if library_version.blank? || library_version.editable?

    errors.add(:base, "Locked library version changes cannot be modified")
  end

  def prevent_destruction
    errors.add(:base, "Library change audit records cannot be deleted")
    throw :abort
  end
end
