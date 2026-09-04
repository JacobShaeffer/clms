require "test_helper"
require "csv"
require "fileutils"
require "tmpdir"
require "zip"
require Rails.root.join("db/real_world_data_seeder").to_s

class RealWorldDataSeederTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @temporary_directory = Dir.mktmpdir("real-world-seeder-test-")
    @csv_path = File.join(@temporary_directory, "contents.csv")
    @archive_path = File.join(@temporary_directory, "documents.zip")
    @output = StringIO.new
  end

  teardown do
    ActiveStorage::Blob.find_each { |blob| blob.service.delete(blob.key) }
    FileUtils.remove_entry(@temporary_directory) if Dir.exist?(@temporary_directory)
  end

  test "tracked real-world CSV contains the expected supported content rows" do
    seeder = RealWorldDataSeeder.new(
      csv_path: RealWorldDataSeeder::DEFAULT_CSV_PATH,
      archive_path: @archive_path,
      output: @output
    )

    rows = seeder.send(:read_rows)

    assert_equal 111, rows.length
    assert_equal 111, rows.map { |row| row.title.downcase }.uniq.length
    assert_equal 111, rows.map { |row| row.filename.downcase }.uniq.length
    assert_equal({ ".pdf" => 102, ".mp4" => 9 }, rows.map { |row| File.extname(row.filename).downcase }.tally)
    assert rows.all? { |row| row.declared_size <= RealWorldDataSeeder::MAX_FILE_SIZE }
  end

  test "rebuilds users content attachments and conservatively normalized metadata" do
    existing_user = User.create!(
      name: "Existing user",
      email: "existing@example.com",
      password: "password"
    )
    pdf = "%PDF-1.4\nreal-world-pdf\n".b
    mp4 = "\x00\x00\x00\x18ftypmp42real-world-video".b
    write_csv([
      build_row(
        title: "  First guide  ",
        display_title: " First display title ",
        filename: "First Guide.pdf",
        description: " First description. ",
        bytes: pdf,
        declared_size: pdf.bytesize + 7,
        metadata: {
          "Collection Type" => " Health Library | Education Library ",
          "Keywords" => " Health   Care | health care | العربية │ Arabic ",
          "Language" => "English"
        }
      ),
      build_row(
        title: "Second video",
        display_title: "Second display title",
        filename: "فيديو المجتمع.mp4",
        description: "Second description.",
        bytes: mp4,
        year: nil,
        metadata: {
          "Collection Type" => "Health Library",
          "Keywords" => "Prevention",
          "Language" => "العربية | Arabic"
        }
      )
    ])
    write_zip([
      [ "documents/First Guide.pdf", pdf ],
      [ "documents/فيديو المجتمع.mp4", mp4 ],
      [ "documents/notes.txt", "unused" ],
      [ "__MACOSX/documents/._First Guide.pdf", "ignored" ],
      [ "documents/.DS_Store", "ignored" ]
    ])

    RealWorldDataSeeder.call(csv_path: @csv_path, archive_path: @archive_path, output: @output)

    refute User.exists?(existing_user.id)
    assert_equal User::ROLES.length, User.count
    assert_equal User::ROLES.keys.map(&:to_s).sort, User.order(:role).pluck(:role).sort
    assert_equal RealWorldDataSeeder::METADATA_TYPE_NAMES, MetadataType.order(:order).pluck(:name)
    assert MetadataType.all.all? { |type| type.access_level == User.roles.fetch("guest") }
    assert Metadatum.all.none?(&:under_review?)

    first = Content.find_by!(title: "First guide")
    second = Content.find_by!(title: "Second video")
    assert_equal "First display title", first.display_title
    assert_equal "First description.", first.description
    assert_equal 2026, first.year_of_publication
    assert_nil second.year_of_publication
    assert_equal "First Guide.pdf", first.file.filename.to_s
    assert_equal "application/pdf", first.file.content_type
    assert_equal pdf, first.file.download
    assert_equal "video/mp4", second.file.content_type
    assert_equal mp4, second.file.download

    keywords = MetadataType.find_by!(name: "Keywords").metadata.order(:id).pluck(:name)
    assert_equal [ "Health Care", "العربية │ Arabic", "Prevention" ], keywords
    assert_equal [ "Health Library", "Education Library" ],
      MetadataType.find_by!(name: "Collection Type").metadata.order(:id).pluck(:name)
    assert_equal [ "العربية", "Arabic" ], second.metadata.joins(:metadata_type)
      .where(metadata_types: { name: "Language" }).order(:id).pluck(:name)
    assert_empty Shelf.all
    assert_empty Library.all
    assert_empty LibraryAsset.all

    assert_includes @output.string,
      "Warning: size mismatch for First Guide.pdf: CSV=#{pdf.bytesize + 7}, ZIP=#{pdf.bytesize} bytes"
    assert_includes @output.string, "Warning: unused ZIP entry: notes.txt"
    assert_includes @output.string, "Imported 2/2: فيديو المجتمع.mp4"
    assert_includes @output.string, "Created real-world development data:"
  end

  test "missing document fails before existing data is reset" do
    write_csv([ build_row(filename: "Missing.pdf") ])
    write_zip([ [ "Other.pdf", "%PDF-other" ] ])

    assert_preflight_failure("Document ZIP is missing files: Missing.pdf")
  end

  test "duplicate archive basenames fail before existing data is reset" do
    write_csv([ build_row(filename: "Repeated.pdf") ])
    write_zip([
      [ "one/Repeated.pdf", "%PDF-one" ],
      [ "two/Repeated.pdf", "%PDF-two" ]
    ])

    assert_preflight_failure("Document ZIP contains duplicate basenames: Repeated.pdf")
  end

  test "unsupported CSV file type fails before existing data is reset" do
    write_csv([ build_row(filename: "Unsupported.docx") ])
    write_zip([ [ "Unsupported.docx", "document" ] ])

    assert_preflight_failure("unsupported file type .docx")
  end

  test "missing required CSV column fails before existing data is reset" do
    headers = RealWorldDataSeeder::REQUIRED_HEADERS - [ "Description" ]
    CSV.open(@csv_path, "wb", headers:, write_headers: true) do |csv|
      csv << headers.index_with { "value" }
    end
    write_zip([])

    assert_preflight_failure("CSV is missing required columns: Description")
  end

  test "empty CSV fails before existing data is reset" do
    write_csv([])
    write_zip([])

    assert_preflight_failure("CSV contains no content rows.")
  end

  test "case-insensitive duplicate titles fail before existing data is reset" do
    write_csv([
      build_row(title: "Repeated title", filename: "First.pdf"),
      build_row(title: " repeated TITLE ", filename: "Second.pdf")
    ])
    write_zip([])

    assert_preflight_failure("CSV contains duplicate titles: Repeated title (rows 2, 3)")
  end

  test "case-insensitive duplicate filenames fail before existing data is reset" do
    write_csv([
      build_row(title: "First", filename: "Repeated.pdf"),
      build_row(title: "Second", filename: "repeated.PDF")
    ])
    write_zip([])

    assert_preflight_failure("CSV contains duplicate filenames: Repeated.pdf (rows 2, 3)")
  end

  test "blank required row value fails before existing data is reset" do
    write_csv([ build_row(description: "  ") ])
    write_zip([])

    assert_preflight_failure("CSV row 2 is missing Description.")
  end

  test "oversized archive document is rejected" do
    write_csv([ build_row(filename: "Large.pdf") ])
    seeder = new_seeder
    row = seeder.send(:read_rows).first
    entry_class = Struct.new(:name, :size) do
      def encrypted?
        false
      end
    end
    entry = entry_class.new("Large.pdf", RealWorldDataSeeder::MAX_FILE_SIZE + 1)

    error = assert_raises(RealWorldDataSeeder::InputError) do
      seeder.send(:validate_archive_entry!, row, entry)
    end

    assert_includes error.message, "Document exceeds the 256 MB limit: Large.pdf"
  end

  private

  def new_seeder
    RealWorldDataSeeder.new(csv_path: @csv_path, archive_path: @archive_path, output: @output)
  end

  def assert_preflight_failure(message)
    existing_user = User.create!(
      name: "Existing user",
      email: "existing-#{SecureRandom.hex(4)}@example.com",
      password: "password"
    )

    error = assert_raises(RealWorldDataSeeder::InputError) do
      RealWorldDataSeeder.call(csv_path: @csv_path, archive_path: @archive_path, output: @output)
    end

    assert_includes error.message, message
    assert User.exists?(existing_user.id), "preflight failure reset existing data"
  end

  def build_row(
    title: "Guide",
    display_title: "Guide display title",
    filename: "Guide.pdf",
    description: "Guide description.",
    bytes: "%PDF-guide",
    declared_size: nil,
    year: 2026,
    metadata: {}
  )
    RealWorldDataSeeder::REQUIRED_HEADERS.index_with(nil).merge(
      "Title" => title,
      "Display Title" => display_title,
      "File Name" => filename,
      "Description" => description,
      "Year Published" => year,
      "Filesize" => declared_size || bytes.bytesize,
      **metadata
    )
  end

  def write_csv(rows)
    CSV.open(
      @csv_path,
      "wb",
      headers: RealWorldDataSeeder::REQUIRED_HEADERS,
      write_headers: true
    ) do |csv|
      rows.each { |row| csv << row }
    end
  end

  def write_zip(entries)
    Zip::OutputStream.open(@archive_path) do |zip|
      entries.each do |name, bytes|
        zip.put_next_entry(name)
        zip.write(bytes)
      end
    end
  end
end
