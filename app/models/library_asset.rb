class LibraryAsset < ApplicationRecord
  LANGUAGES = %w[ English French Spanish Arabic ].freeze
  ASSET_TYPES = %w[ Banner Subject Module ].freeze

  belongs_to :user

  has_one_attached :image
  has_one_attached :design_files

  has_many :library_folders,
    foreign_key: :logo_id,
    inverse_of: :logo,
    dependent: :restrict_with_error
  has_many :library_modules,
    foreign_key: :icon_id,
    inverse_of: :icon,
    dependent: :restrict_with_error
  has_many :banner_libraries,
    class_name: "Library",
    foreign_key: :banner_id,
    inverse_of: :banner,
    dependent: :restrict_with_error

  validates :name, uniqueness: { case_sensitive: false, message: "Name must be unique" }, allow_blank: true
  validates :asset_type, inclusion: { in: ASSET_TYPES }, allow_blank: true
  validates :image, presence: true,
                    blob: { content_type: "image/png" }
  validates :design_files, blob: { content_type: [ "application/zip", "application/x-zip-compressed" ] }
  validate :banner_type_when_assigned

  def display_name
    name.presence || (image.filename.to_s if image.attached?) || "Library asset"
  end

  private

  def banner_type_when_assigned
    return if asset_type == "Banner" || banner_libraries.empty?

    errors.add(:asset_type, "must remain Banner while used by a library")
  end
end
