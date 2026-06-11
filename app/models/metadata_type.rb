class MetadataType < ApplicationRecord
  belongs_to :user
  has_many :metadata, dependent: :destroy

  validates :name, presence: true, allow_blank: false, uniqueness: { case_sensitive: false, message: "Name must be unique" }
end
