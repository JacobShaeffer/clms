class LibraryAsset < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, allow_blank: false,
                   uniqueness: { case_sensitive: false, message: "Name must be unique" }

  has_one_attached :image
  has_one_attached :design_documents
end
