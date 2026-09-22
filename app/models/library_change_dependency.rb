class LibraryChangeDependency < ApplicationRecord
  belongs_to :library_change, inverse_of: :dependency_links
  belongs_to :prerequisite_change,
    class_name: "LibraryChange",
    inverse_of: :dependent_links

  validates :prerequisite_change_id, uniqueness: { scope: :library_change_id }
  validate :changes_belong_to_same_version
  validate :prerequisite_is_older
  validate :dependent_change_accepts_dependencies, on: :create

  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def changes_belong_to_same_version
    return if library_change.blank? || prerequisite_change.blank?
    return if library_change.library_version_id == prerequisite_change.library_version_id

    errors.add(:prerequisite_change, "must belong to the same library version")
  end

  def prerequisite_is_older
    return if library_change_id.blank? || prerequisite_change_id.blank?
    return if prerequisite_change_id < library_change_id

    errors.add(:prerequisite_change, "must be older than the dependent change")
  end

  def dependent_change_accepts_dependencies
    return if library_change.blank?
    return if library_change.pending? && library_change.library_version.editable?

    errors.add(:library_change, "must be pending in an editable version")
  end

  def prevent_mutation
    errors.add(:base, "Library change dependencies cannot be modified")
    throw :abort
  end
end
