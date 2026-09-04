require "csv"
require "pathname"
require "tempfile"
require "zip"
require_relative "development_seed_support"

class RealWorldDataSeeder
  class InputError < StandardError; end

  DEFAULT_CSV_PATH = Rails.root.join("db/real_world_data/contents.csv")
  DEFAULT_ARCHIVE_PATH = Rails.root.join("tmp/real_world_documents.zip")
  MAX_FILE_SIZE = 256.megabytes

  CORE_HEADERS = [ "Title", "Display Title", "File Name", "Description", "Year Published", "Filesize" ].freeze
  METADATA_TYPE_NAMES = [
    "Collection Type",
    "Author",
    "Rights Holder",
    "Rights Statement",
    "Library User",
    "Education Level",
    "Subject",
    "Subcategory",
    "Keywords",
    "Resource Type",
    "Format",
    "Language"
  ].freeze
  REQUIRED_HEADERS = (CORE_HEADERS + METADATA_TYPE_NAMES).freeze
  CONTENT_TYPES = {
    ".pdf" => "application/pdf",
    ".mp4" => "video/mp4"
  }.freeze

  Row = Data.define(
    :number,
    :title,
    :display_title,
    :filename,
    :description,
    :year_of_publication,
    :declared_size,
    :content_type,
    :metadata
  )
  ArchiveFile = Data.define(:entry_name, :size)

  def self.call(csv_path: DEFAULT_CSV_PATH, archive_path: DEFAULT_ARCHIVE_PATH, output: $stdout)
    new(csv_path:, archive_path:, output:).call
  end

  def initialize(csv_path:, archive_path:, output:)
    @csv_path = Pathname(csv_path)
    @archive_path = Pathname(archive_path)
    @output = output
  end

  def call
    rows, archive_files = preflight!
    DevelopmentSeedSupport.reset_data!
    users = DevelopmentSeedSupport.create_users!
    admin = users.fetch("admin")
    metadata = create_metadata!(rows:, admin:)
    create_contents!(rows:, archive_files:, metadata:, admin:)
    print_summary(rows:, users:)
  end

  private

  attr_reader :csv_path, :archive_path, :output

  def preflight!
    validate_input_files!
    rows = read_rows
    validate_unique_rows!(rows)
    archive_files = inspect_archive(rows)

    output.puts "Preflight passed for #{rows.length} real-world content rows."
    [ rows, archive_files ]
  rescue CSV::MalformedCSVError => error
    raise InputError, "Could not parse #{csv_path}: #{error.message}"
  rescue Zip::Error => error
    raise InputError, "Could not read #{archive_path}: #{error.message}"
  end

  def validate_input_files!
    raise InputError, "CSV file not found: #{csv_path}" unless csv_path.file?
    raise InputError, "Document ZIP not found: #{archive_path}" unless archive_path.file?
  end

  def read_rows
    table = CSV.read(csv_path, headers: true, encoding: "bom|utf-8")
    validate_headers!(table.headers)
    raise InputError, "CSV contains no content rows." if table.empty?

    table.each_with_index.map do |csv_row, index|
      build_row(csv_row, index + 2)
    end
  end

  def validate_headers!(headers)
    missing_headers = REQUIRED_HEADERS - Array(headers)
    return if missing_headers.empty?

    raise InputError, "CSV is missing required columns: #{missing_headers.join(', ')}"
  end

  def build_row(csv_row, row_number)
    raise InputError, "CSV row #{row_number} has more values than headers." if csv_row.to_h.key?(nil)

    title = required_text(csv_row, "Title", row_number)
    display_title = required_text(csv_row, "Display Title", row_number)
    filename = normalized_filename(required_text(csv_row, "File Name", row_number), row_number)
    description = required_text(csv_row, "Description", row_number)
    extension = File.extname(filename).downcase
    content_type = CONTENT_TYPES[extension]
    unless content_type
      raise InputError,
        "CSV row #{row_number} has unsupported file type #{extension.presence || '(none)'} for #{filename}."
    end

    Row.new(
      number: row_number,
      title:,
      display_title:,
      filename:,
      description:,
      year_of_publication: optional_integer(csv_row["Year Published"], "Year Published", row_number),
      declared_size: required_integer(csv_row["Filesize"], "Filesize", row_number),
      content_type:,
      metadata: METADATA_TYPE_NAMES.to_h do |type_name|
        [ type_name, metadata_values(csv_row[type_name]) ]
      end
    )
  end

  def required_text(csv_row, header, row_number)
    value = normalized_text(csv_row[header])
    return value if value.present?

    raise InputError, "CSV row #{row_number} is missing #{header}."
  end

  def normalized_filename(filename, row_number)
    normalized = filename.unicode_normalize(:nfc)
    if normalized.include?("/") || normalized.include?("\\")
      raise InputError, "CSV row #{row_number} File Name must be a basename: #{filename}"
    end

    normalized
  end

  def normalized_text(value)
    value.to_s.unicode_normalize(:nfc).strip
  end

  def normalized_metadata_value(value)
    normalized_text(value).gsub(/[[:space:]]+/, " ")
  end

  def metadata_values(value)
    seen = {}
    value.to_s.split("|").filter_map do |part|
      normalized = normalized_metadata_value(part)
      next if normalized.blank?

      key = comparison_key(normalized)
      next if seen[key]

      seen[key] = true
      normalized
    end
  end

  def required_integer(value, header, row_number)
    parsed = parse_integer(value)
    return parsed if parsed && parsed >= 0

    raise InputError, "CSV row #{row_number} has invalid #{header}: #{value.inspect}"
  end

  def optional_integer(value, header, row_number)
    return if value.blank?

    parsed = parse_integer(value)
    return parsed if parsed&.positive?

    raise InputError, "CSV row #{row_number} has invalid #{header}: #{value.inspect}"
  end

  def parse_integer(value)
    Integer(value.to_s.strip, 10, exception: false)
  end

  def validate_unique_rows!(rows)
    validate_unique_attribute!(rows, :title, "titles")
    validate_unique_attribute!(rows, :filename, "filenames")
  end

  def validate_unique_attribute!(rows, attribute, label)
    duplicates = rows.group_by { |row| comparison_key(row.public_send(attribute)) }
      .values
      .select { |group| group.length > 1 }
    return if duplicates.empty?

    details = duplicates.map do |group|
      "#{group.first.public_send(attribute)} (rows #{group.map(&:number).join(', ')})"
    end
    raise InputError, "CSV contains duplicate #{label}: #{details.join('; ')}"
  end

  def comparison_key(value)
    value.unicode_normalize(:nfc).downcase
  end

  def inspect_archive(rows)
    archive_entries = usable_archive_entries
    entries_by_basename = archive_entries.group_by { |entry| archive_basename(entry) }
    duplicate_names = entries_by_basename.select { |_name, entries| entries.length > 1 }.keys
    if duplicate_names.any?
      raise InputError, "Document ZIP contains duplicate basenames: #{duplicate_names.sort.join(', ')}"
    end

    entries_by_basename.transform_values!(&:first)
    expected_names = rows.map(&:filename)
    missing_names = expected_names - entries_by_basename.keys
    if missing_names.any?
      raise InputError, "Document ZIP is missing files: #{missing_names.sort.join(', ')}"
    end

    rows.to_h do |row|
      entry = entries_by_basename.fetch(row.filename)
      validate_archive_entry!(row, entry)
      [ row.filename, ArchiveFile.new(entry_name: entry.name, size: entry.size) ]
    end.tap do
      unused_names = entries_by_basename.keys - expected_names
      unused_names.sort.each { |name| output.puts "Warning: unused ZIP entry: #{name}" }
    end
  end

  def usable_archive_entries
    Zip::File.open(archive_path) do |archive|
      archive.entries.reject { |entry| ignored_archive_entry?(entry) }
    end
  end

  def ignored_archive_entry?(entry)
    return true if entry.directory?

    path_parts = normalized_archive_entry_name(entry).split("/")
    basename = path_parts.last
    path_parts.include?("__MACOSX") || basename == ".DS_Store" || basename&.start_with?("._")
  end

  def archive_basename(entry)
    File.basename(normalized_archive_entry_name(entry))
  end

  def normalized_archive_entry_name(entry)
    name = entry.name.tr("\\", "/").dup.force_encoding(Encoding::UTF_8)
    raise Encoding::InvalidByteSequenceError, "filename is not valid UTF-8" unless name.valid_encoding?

    name.unicode_normalize(:nfc)
  rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError => error
    raise InputError, "Document ZIP contains an invalid filename: #{error.message}"
  end

  def validate_archive_entry!(row, entry)
    raise InputError, "Document ZIP entry is encrypted: #{entry.name}" if entry.encrypted?
    if entry.size > MAX_FILE_SIZE
      raise InputError, "Document exceeds the 256 MB limit: #{row.filename} (#{entry.size} bytes)"
    end
    return if entry.size == row.declared_size

    output.puts "Warning: size mismatch for #{row.filename}: CSV=#{row.declared_size}, ZIP=#{entry.size} bytes"
  end

  def create_metadata!(rows:, admin:)
    METADATA_TYPE_NAMES.each_with_index.to_h do |type_name, index|
      type = MetadataType.create!(
        name: type_name,
        order: index + 1,
        access_level: User.roles.fetch("guest"),
        user: admin
      )
      values_by_key = {}
      rows.each do |row|
        row.metadata.fetch(type_name).each do |value_name|
          values_by_key[comparison_key(value_name)] ||= type.metadata.create!(
            name: value_name,
            under_review: false,
            user: admin
          )
        end
      end

      [ type_name, values_by_key ]
    end
  end

  def create_contents!(rows:, archive_files:, metadata:, admin:)
    Zip::File.open(archive_path) do |archive|
      rows.each_with_index do |row, index|
        create_content!(
          row:,
          archive:,
          archive_file: archive_files.fetch(row.filename),
          metadata:,
          admin:
        )
        output.puts "Imported #{index + 1}/#{rows.length}: #{row.filename}"
      end
    end
  end

  def create_content!(row:, archive:, archive_file:, metadata:, admin:)
    entry = archive.find_entry(archive_file.entry_name)
    raise InputError, "Document ZIP entry disappeared: #{archive_file.entry_name}" unless entry

    Tempfile.create([ "real-world-content-", File.extname(row.filename) ]) do |file|
      file.binmode
      entry.get_input_stream { |input| IO.copy_stream(input, file, MAX_FILE_SIZE + 1) }
      file.flush
      if file.size > MAX_FILE_SIZE
        raise InputError, "Document exceeds the 256 MB limit while reading: #{row.filename}"
      end
      if file.size != archive_file.size
        raise InputError, "Could not completely read #{row.filename} from the document ZIP."
      end
      file.rewind

      content = Content.new(
        user: admin,
        title: row.title,
        display_title: row.display_title,
        description: row.description,
        year_of_publication: row.year_of_publication
      )
      content.file.attach(
        io: file,
        filename: row.filename,
        content_type: row.content_type,
        identify: false
      )
      content.save!
      attach_metadata!(content:, row:, metadata:)
    end
  rescue InputError
    raise
  rescue StandardError => error
    raise InputError, "Failed to import CSV row #{row.number} (#{row.filename}): #{error.message}"
  end

  def attach_metadata!(content:, row:, metadata:)
    METADATA_TYPE_NAMES.each do |type_name|
      values_by_key = metadata.fetch(type_name)
      row.metadata.fetch(type_name).each do |value_name|
        ContentMetadatum.create!(
          content:,
          metadata: values_by_key.fetch(comparison_key(value_name))
        )
      end
    end
  end

  def print_summary(rows:, users:)
    output.puts "Created real-world development data:"
    output.puts "  #{users.length} users"
    output.puts "  #{MetadataType.count} metadata types and #{Metadatum.count} metadata values"
    output.puts "  #{rows.length} contents with attached documents"
    output.puts "  0 shelves and 0 libraries"
    output.puts "Development credentials: role@role.com / rolerole"
  end
end
