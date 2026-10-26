class LibraryBuild < ApplicationRecord
  belongs_to :library_version
  belongs_to :user

  # These references protect files only while an export attempt is running.
  has_many_attached :working_files

  enum :status, %w[ queued exporting ready failed ].index_with(&:itself), validate: true

  validates :library_version_id, uniqueness: true
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :requested_at, presence: true
  validate :version_is_locked

  def published?
    published_generation.present?
  end

  private

  def version_is_locked
    return if library_version&.locked?

    errors.add(:library_version, "must be locked")
  end
end
