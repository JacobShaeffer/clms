class LibraryVersion < ApplicationRecord
  belongs_to :library, inverse_of: :library_versions
  belongs_to :user
  belongs_to :previous_version, class_name: "LibraryVersion", optional: true

  has_one :next_version,
    class_name: "LibraryVersion",
    foreign_key: :previous_version_id,
    inverse_of: :previous_version,
    dependent: :restrict_with_error

  validates :version_number,
    presence: true,
    uniqueness: { scope: :library_id }
  validate :previous_version_belongs_to_library

  before_validation :assign_previous_version, on: :create
  after_create :make_current!

  private

  def assign_previous_version
    return if library.blank? || library.new_record?

    library.with_lock do
      self.previous_version = library.current_version
    end
  end

  def make_current!
    library.update!(current_version: self)
  end

  def previous_version_belongs_to_library
    return if previous_version.blank? || previous_version.library_id == library_id

    errors.add(:previous_version, "must belong to this library")
  end
end
