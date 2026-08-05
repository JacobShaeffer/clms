class Library < ApplicationRecord
  INITIAL_VERSION_NUMBER = "1.0"

  belongs_to :user
  belongs_to :current_version, class_name: "LibraryVersion", optional: true

  has_many :library_versions, inverse_of: :library, dependent: :restrict_with_error
  has_many :library_folders, inverse_of: :library, dependent: :restrict_with_error

  validates :name, presence: true
  validates :current_version, presence: true, on: :update
  validate :current_version_belongs_to_library

  after_create :create_initial_version!

  private

  def create_initial_version!
    library_versions.create!(
      user: user,
      version_number: INITIAL_VERSION_NUMBER
    )
  end

  def current_version_belongs_to_library
    return if current_version.blank? || current_version.library_id == id

    errors.add(:current_version, "must belong to this library")
  end
end
