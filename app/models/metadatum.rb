class Metadatum < ApplicationRecord
  belongs_to :user
  belongs_to :metadata_type

  has_many :contents_metadata, class_name: "ContentMetadatum", foreign_key: "metadata_id", dependent: :destroy
  has_many :contents, through: :contents_metadata

  validates :name, presence: true, allow_blank: false, uniqueness: { case_sensitive: false, scope: :metadata_type_id, message: "Name must be unique within the same metadata type" }

  scope :by_metadata_type, ->(metadata_type_id) { where(metadata_type_id: metadata_type_id) }
  scope :by_under_review, ->(under_review) { where(under_review: under_review) }
end
