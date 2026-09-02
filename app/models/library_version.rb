class LibraryVersion < ApplicationRecord
  belongs_to :library, inverse_of: :library_versions
  belongs_to :user
  belongs_to :previous_version, class_name: "LibraryVersion", optional: true

  has_many :library_folders,
    inverse_of: :library_version,
    dependent: :restrict_with_error
  has_many :library_folder_contents,
    inverse_of: :library_version,
    dependent: :restrict_with_error
  has_many :library_version_contents,
    inverse_of: :library_version,
    dependent: :restrict_with_error
  has_many :contents, through: :library_version_contents

  has_one :next_version,
    class_name: "LibraryVersion",
    foreign_key: :previous_version_id,
    inverse_of: :previous_version,
    dependent: :restrict_with_error

  validates :version_number,
    presence: true,
    uniqueness: { scope: :library_id }
  validate :previous_version_belongs_to_library
  validate :locked_version_is_immutable, on: :update

  before_validation :normalize_version_number
  before_destroy :prevent_locked_version_destruction, prepend: true

  def locked?
    locked_at.present?
  end

  def editable?
    !locked?
  end

  def ensure_content_manifest!(content)
    if locked? || locked_in_database?
      raise ActiveRecord::ReadOnlyRecord, "Library version is locked"
    end

    existing_manifest = library_version_contents.find_by(content:)
    return existing_manifest if existing_manifest

    library_version_contents.create_or_find_by!(content:) do |manifest|
      manifest.file_checksum = content.file.blob.checksum if content.file.attached?
    end
  rescue ActiveRecord::RecordInvalid => error
    existing_manifest = library_version_contents.find_by(content:)
    return existing_manifest if existing_manifest

    raise error
  end

  def file_changed_content_ids(scope_or_contents = contents)
    return [] unless previous_version

    content_ids = content_ids_from(scope_or_contents)
    return [] if content_ids.empty?

    previous_checksums = previous_version.library_version_contents
      .where(content_id: content_ids)
      .pluck(:content_id, :file_checksum)
      .to_h
    return [] if previous_checksums.empty?

    current_checksums = if locked? || locked_in_database?
      library_version_contents
        .where(content_id: previous_checksums.keys)
        .pluck(:content_id, :file_checksum)
        .to_h
    else
      live_content_checksums(scope_or_contents, previous_checksums.keys)
    end

    previous_checksums.filter_map do |content_id, previous_checksum|
      content_id if current_checksums.key?(content_id) && current_checksums[content_id] != previous_checksum
    end
  end

  private

  def content_ids_from(scope_or_contents)
    if scope_or_contents.respond_to?(:ids)
      scope_or_contents.ids
    else
      Array(scope_or_contents).filter_map do |content|
        content.respond_to?(:content_id) ? content.content_id : content.id
      end
    end.uniq
  end

  def live_content_checksums(scope_or_contents, content_ids)
    supplied_contents = Array(scope_or_contents) if scope_or_contents.is_a?(Array)
    content_records = if supplied_contents&.all? { |content| content.is_a?(Content) }
      content_ids_by_id = content_ids.index_with(true)
      supplied_contents.select { |content| content_ids_by_id.key?(content.id) }
    else
      Content.where(id: content_ids).with_attached_file
    end

    content_records.to_h do |content|
      checksum = content.file.blob.checksum if content.file.attached?
      [ content.id, checksum ]
    end
  end

  def normalize_version_number
    self.version_number = version_number.strip if version_number.respond_to?(:strip)
  end

  def previous_version_belongs_to_library
    return if previous_version.blank? || previous_version.library_id == library_id

    errors.add(:previous_version, "must belong to this library")
  end

  def locked_version_is_immutable
    return unless has_changes_to_save?
    return if locked_at_in_database.blank? && !locked_in_database?

    errors.add(:base, "Locked library versions cannot be changed")
  end

  def prevent_locked_version_destruction
    return unless locked_at_in_database.present? || locked_in_database?

    errors.add(:base, "Locked library versions cannot be deleted")
    throw :abort
  end

  def locked_in_database?
    persisted? && self.class.where(id:).where.not(locked_at: nil).exists?
  end
end
