class LibraryAsset < ApplicationRecord
  belongs_to :user

  has_one_attached :image
  has_one_attached :design_files

  validates :name, presence: true, allow_blank: false,
                   uniqueness: { case_sensitive: false, message: "Name must be unique" }
  validates :image, presence: true,
                    blob: { content_type: "image/png" }
  validates :design_files, presence: true,
                           blob: { content_type: [ "application/zip", "application/x-zip-compressed" ] }
end
