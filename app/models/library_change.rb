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
  STATUSES = { pending: "pending", approved: "approved", undone: "undone" }.freeze

  belongs_to :library_version
  belongs_to :user
  belongs_to :resolved_by, class_name: "User", optional: true

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
  has_many :pending_removed_folders,
    class_name: "LibraryFolder",
    foreign_key: :pending_removal_change_id,
    inverse_of: :pending_removal_change,
    dependent: :restrict_with_error
  has_many :pending_removed_placements,
    class_name: "LibraryFolderContent",
    foreign_key: :pending_removal_change_id,
    inverse_of: :pending_removal_change,
    dependent: :restrict_with_error

  enum :action_type, ACTION_TYPES, validate: true
  enum :status, STATUSES, validate: true

  validates :batch_key, presence: true
  validates :details, presence: true
  validate :resolution_is_complete
  validate :resolved_change_is_immutable, on: :update
  validate :library_version_is_editable, on: %i[create update]

  before_destroy :prevent_destruction, prepend: true

  scope :ordered, -> { order(:created_at, :id) }

  def approval_blocker
    prerequisites.where.not(status: :approved).ordered.first
  end

  def undo_blocker
    dependents.pending.ordered.first
  end

  def approvable?
    pending? && approval_blocker.nil?
  end

  def undoable?
    pending? && undo_blocker.nil?
  end

  def direct_target
    library_change_targets.find(&:direct?)
  end

  def display_label
    direct_target&.label || action_type.humanize
  end

  private

  def resolution_is_complete
    if pending?
      errors.add(:resolved_at, "must be blank while pending") if resolved_at.present?
      errors.add(:resolved_by, "must be blank while pending") if resolved_by.present?
    else
      errors.add(:resolved_at, "must be present") if resolved_at.blank?
      errors.add(:resolved_by, "must be present") if resolved_by.blank?
    end
  end

  def resolved_change_is_immutable
    return if status_in_database == "pending"
    return unless has_changes_to_save?

    errors.add(:base, "Resolved library changes cannot be modified")
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
