class Content < ApplicationRecord
  ALLOWED_FILE_CONTENT_TYPES = [ "application/pdf", "audio/mpeg", "video/mp4" ].freeze
  ALLOWED_FILE_EXTENSIONS = [ ".pdf", ".mp3", ".mp4" ].freeze

  belongs_to :user

  has_many :shelf_contents, dependent: :destroy
  has_many :shelves, through: :shelf_contents

  has_many :library_folder_contents, dependent: :restrict_with_error
  has_many :library_folders, through: :library_folder_contents
  has_many :library_version_contents, dependent: :restrict_with_error
  has_many :library_versions, through: :library_version_contents

  has_many :contents_metadata, class_name: "ContentMetadatum", dependent: :destroy
  has_many :metadata, through: :contents_metadata

  has_one_attached :file

  validates :title, presence: true, allow_blank: false
  validates :display_title, presence: true, allow_blank: false
  validates :description, presence: true, allow_blank: false
  validates :file, presence: true,
                   blob: {
                     content_type: ALLOWED_FILE_CONTENT_TYPES,
                     extension: ALLOWED_FILE_EXTENSIONS,
                     size_range: 0..(256.megabytes)
                   }

  validate :title_must_be_unique
  validate :file_checksum_must_be_unique
  validate :file_filename_must_be_unique

  scope :active, -> { where(trashed_at: nil) }
  scope :trashed, -> { where.not(trashed_at: nil) }

  def trashed?
    trashed_at.present?
  end

  def trash!(comment: nil)
    update_columns(
      trashed_at: Time.current,
      trash_comment: comment.to_s.strip.presence,
      updated_at: Time.current
    )
  end

  def restore!
    update_columns(trashed_at: nil, trash_comment: nil, updated_at: Time.current)
  end

  private

  def title_must_be_unique
    return if title.blank?

    duplicate_content = Content.where.not(id: id)
      .find_by("LOWER(title) = ?", title.downcase)
    return unless duplicate_content

    message = if duplicate_content.trashed?
      "is already used by content in Trash: #{duplicate_content.title}"
    else
      "Title must be unique"
    end
    errors.add(:title, message)
  end

  def file_checksum_must_be_unique
    return unless file.attached?

    duplicate_content = Content.joins(file_attachment: :blob)
                               .where.not(id: id)
                               .find_by(active_storage_blobs: { checksum: file.blob.checksum })
    return if duplicate_content.blank?

    existing_file_title = duplicate_content.title

    message = if duplicate_content.trashed?
      "File already exists in Trash with title: #{existing_file_title}"
    else
      "File already exists with title: #{existing_file_title}"
    end
    errors.add(:file, message)
  end

  def file_filename_must_be_unique
    return unless file.attached?

    duplicate_content = Content.joins(file_attachment: :blob)
                               .where.not(id: id)
                               .find_by("LOWER(active_storage_blobs.filename) = ?", file.blob.filename.to_s.downcase)
    return if duplicate_content.blank?

    existing_file_title = duplicate_content.title

    message = if duplicate_content.trashed?
      "A file with the same filename exists in Trash with title: #{existing_file_title}"
    else
      "A file with the same filename already exists with title: #{existing_file_title}"
    end
    errors.add(:file, message)
  end
end
