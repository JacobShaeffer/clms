class Metadatum < ApplicationRecord
  belongs_to :user
  belongs_to :metadata_type

  has_many :contents_metadata, class_name: "ContentMetadatum", foreign_key: "metadata_id", dependent: :destroy
  has_many :contents, through: :contents_metadata

  validates :name, presence: true, allow_blank: false, uniqueness: { case_sensitive: false, scope: :metadata_type_id, message: "Name must be unique within the same metadata type" }

  scope :by_metadata_type, ->(metadata_type_id) { where(metadata_type_id: metadata_type_id) }
  scope :by_under_review, ->(under_review) { where(under_review: under_review) }

  def replace_with!(replacement)
    unless persisted? && replacement&.persisted? && replacement.id != id && replacement.metadata_type_id == metadata_type_id
      raise ArgumentError, "Replacement must be a different persisted value from the same metadata type"
    end

    transaction do
      contents_metadata
        .where(content_id: replacement.contents_metadata.select(:content_id))
        .delete_all
      contents_metadata.update_all(metadata_id: replacement.id, updated_at: Time.current)
      destroy!
    end

    replacement
  end
end
