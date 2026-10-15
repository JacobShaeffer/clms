class Library < ApplicationRecord
  INITIAL_VERSION_NUMBER = "1.0"

  belongs_to :user
  belongs_to :current_version, class_name: "LibraryVersion", optional: true
  belongs_to :banner,
    class_name: "LibraryAsset",
    inverse_of: :banner_libraries,
    optional: true

  has_many :library_versions, inverse_of: :library, dependent: :restrict_with_error
  has_many :library_folders, inverse_of: :library, dependent: :restrict_with_error
  has_many :library_folder_contents, through: :library_folders
  has_many :contents, through: :library_folder_contents

  validates :name, presence: true
  validates :current_version, presence: true, on: :update
  validate :banner_is_banner_asset
  validate :current_version_belongs_to_library
  validate :current_version_is_editable

  after_create :create_initial_version!

  def current_library_folders
    current_version&.library_folders || LibraryFolder.none
  end

  private

  def banner_is_banner_asset
    return if banner.blank? || banner.asset_type == "Banner"

    errors.add(:banner, "must be a Banner library asset")
  end

  def create_initial_version!
    version = library_versions.create!(
      user: user,
      version_number: INITIAL_VERSION_NUMBER
    )
    update!(current_version: version)
  end

  def current_version_belongs_to_library
    return if current_version.blank? || current_version.library_id == id

    errors.add(:current_version, "must belong to this library")
  end

  def current_version_is_editable
    return if current_version.blank?

    locked_in_database = current_version.persisted? &&
      LibraryVersion.where(id: current_version.id).where.not(locked_at: nil).exists?
    return unless current_version.locked? || locked_in_database

    errors.add(:current_version, "must be editable")
  end
end
