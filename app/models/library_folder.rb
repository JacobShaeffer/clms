class LibraryFolder < ApplicationRecord
  belongs_to :library, inverse_of: :library_folders
  belongs_to :parent_folder, class_name: "LibraryFolder", optional: true
  belongs_to :user
  belongs_to :logo, class_name: "LibraryAsset"

  has_many :child_folders,
    class_name: "LibraryFolder",
    foreign_key: :parent_folder_id,
    inverse_of: :parent_folder,
    dependent: :restrict_with_error

  scope :roots, -> { where(parent_folder_id: nil) }

  validates :name, presence: true
  validate :parent_folder_belongs_to_library
  validate :parent_folder_is_not_self

  private

  def parent_folder_belongs_to_library
    return if parent_folder.blank? || parent_folder.library_id == library_id

    errors.add(:parent_folder, "must belong to this library")
  end

  def parent_folder_is_not_self
    return if parent_folder_id.blank? || parent_folder_id != id

    errors.add(:parent_folder, "cannot be itself")
  end
end
