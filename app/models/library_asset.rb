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

  validates :name, uniqueness: { case_sensitive: false, message: "Name must be unique" }, allow_blank: true
  validates :asset_type, inclusion: { in: ASSET_TYPES }, allow_blank: true
  validates :image, presence: true,
                    blob: { content_type: "image/png" }
  validates :design_files, blob: { content_type: [ "application/zip", "application/x-zip-compressed" ] }

  def display_name
    name.presence || (image.filename.to_s if image.attached?) || "Library asset"
  end
end
