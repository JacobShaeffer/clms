class Content < ApplicationRecord
  belongs_to :user

  has_many :shelf_contents, dependent: :destroy
  has_many :shelves, through: :shelf_contents

  has_many :contents_metadata, class_name: "ContentMetadatum", dependent: :destroy
  has_many :metadata, through: :contents_metadata

  has_one_attached :file

  validates :title, presence: true, allow_blank: false,
                    uniqueness: { case_sensitive: false, message: "Title must be unique" }
  validates :display_title, presence: true, allow_blank: false
  validates :description, presence: true, allow_blank: false
  validates :file, presence: true,
                   blob: { content_type: [ "application/pdf", "audio/mpeg", "video/mp4", "image/png" ], size_range: 0..(256.megabytes) }

  validate :file_checksum_must_be_unique
  validate :file_filename_must_be_unique

  private

  def file_checksum_must_be_unique
    return unless file.attached?

    duplicate_content = Content.joins(file_attachment: :blob)
                               .where.not(id: id)
                               .find_by(active_storage_blobs: { checksum: file.blob.checksum })
    return if duplicate_content.blank?

    existing_file_title = duplicate_content.title

    errors.add(:file, "File already exists with title: #{existing_file_title}")
  end

  def file_filename_must_be_unique
    return unless file.attached?

    duplicate_content = Content.joins(file_attachment: :blob)
                               .where.not(id: id)
                               .find_by("LOWER(active_storage_blobs.filename) = ?", file.blob.filename.to_s.downcase)
    return if duplicate_content.blank?

    existing_file_title = duplicate_content.title

    errors.add(:file, "A file with the same filename already exists with title: #{existing_file_title}")
  end
end
