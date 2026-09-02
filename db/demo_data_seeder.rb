require "faker"
require "stringio"

class DemoDataSeeder
  RANDOM_SEED = 20_260_814
  CONTENT_COUNT = 100
  VALUES_PER_METADATA_TYPE = 60
  VALUES_PER_CONTENT_AND_TYPE = 3

  FOLDER_TREE = {
    "Emergency Care" => [ "First Aid", "Injury Response", "Disaster Preparedness" ],
    "Family Health" => [ "Maternal Care", "Child Wellness", "Nutrition" ],
    "Disease Prevention" => [ "Infectious Diseases", "Vaccination", "Hygiene" ],
    "Healthy Communities" => [ "Water and Sanitation", "Environmental Health", "Community Outreach" ],
    "Learning Resources" => [ "Health Education", "Training Guides", "Facilitator Materials" ],
    "Wellbeing" => [ "Mental Health", "Personal Wellness", "Social Support" ]
  }.freeze

  ADDITIONAL_TOPICS = [
    "Adolescent Health", "Aging and Elder Care", "Air Quality", "Antimicrobial Resistance",
    "Assistive Technology", "Chronic Disease", "Climate and Health", "Dental Health",
    "Diabetes", "Digital Health", "Disability Inclusion", "Emergency Communication",
    "Eye Health", "Food Safety", "Gender Equity", "Health Policy",
    "Hearing Health", "Heart Health", "Human Rights", "Infection Control",
    "Malaria", "Medication Safety", "Men's Health", "Noncommunicable Diseases",
    "Occupational Health", "One Health", "Oral Rehydration", "Physical Activity",
    "Respiratory Health", "Road Safety", "School Health", "Sexual Health",
    "Skin Health", "Smoking Prevention", "Snakebite Prevention", "Tuberculosis",
    "Vector Control", "Vision Care", "Waste Management", "Women's Health",
    "Workplace Safety", "Zoonotic Disease"
  ].freeze

  AUDIENCE_GROUPS = [
    "Community Health Workers", "Teachers", "Students", "Parents", "Caregivers",
    "Clinicians", "Volunteers", "Program Managers", "Youth Leaders", "Community Members"
  ].freeze
  AUDIENCE_CONTEXTS = [ "Introductory", "Advanced", "Rural", "Urban", "Classroom", "Field" ].freeze

  REGIONS = [
    "East Africa", "West Africa", "Southern Africa", "North Africa", "Central Africa", "South Asia",
    "Southeast Asia", "Central Asia", "Pacific Islands", "Caribbean", "Latin America", "Middle East"
  ].freeze
  REGION_CONTEXTS = [ "Rural", "Urban", "Coastal", "Highland", "Remote" ].freeze

  LANGUAGES = [
    "Afrikaans", "Amharic", "Arabic", "Bengali", "Bislama", "Burmese", "Cebuano", "Chichewa",
    "Chinese", "Dari", "English", "Fijian", "Filipino", "French", "Gujarati", "Haitian Creole",
    "Hausa", "Hindi", "Hiri Motu", "Indonesian", "Khmer", "Kinyarwanda", "Kiribati", "Korean",
    "Lao", "Lingala", "Luganda", "Malay", "Malayalam", "Marathi", "Marshallese", "Mongolian",
    "Nepali", "Oromo", "Pashto", "Portuguese", "Punjabi", "Samoan", "Sinhala", "Somali",
    "Spanish", "Swahili", "Tagalog", "Tamil", "Telugu", "Tetum", "Thai", "Tigrinya",
    "Tok Pisin", "Tongan", "Turkish", "Tuvaluan", "Urdu", "Vietnamese", "Wolof", "Xhosa",
    "Yoruba", "Zulu", "French Creole", "Solomon Islands Pijin"
  ].freeze

  METADATA_TYPE_NAMES = [ "Topic", "Audience", "Region", "Language", "Publisher" ].freeze

  def self.call(output: $stdout)
    new(output:).call
  end

  def initialize(output:)
    @output = output
  end

  def call
    configure_faker
    reset_data!

    users = create_users!
    admin = users.fetch("admin")
    metadata = create_metadata!(admin)
    contents_by_topic = create_contents!(admin, metadata)
    shelf = create_shelf!(admin, contents_by_topic)
    library = create_library!(admin, contents_by_topic)

    print_summary(users:, shelf:, library:)
  end

  private

  attr_reader :output

  def configure_faker
    Faker::Config.random = Random.new(RANDOM_SEED)
    Faker::UniqueGenerator.clear
  end

  def reset_data!
    purge_active_storage!

    ActiveShelf.delete_all
    ContentTablePreference.delete_all
    LibraryFolderContent.delete_all
    LibraryVersionContent.delete_all
    ShelfContent.delete_all
    ContentMetadatum.delete_all
    Library.update_all(current_version_id: nil)
    LibraryFolder.delete_all
    LibraryVersion.delete_all
    Library.delete_all
    Shelf.delete_all
    Content.delete_all
    Metadatum.delete_all
    MetadataType.delete_all
    LibraryAsset.delete_all
    User.delete_all
  end

  def purge_active_storage!
    ActiveStorage::Blob.find_each(&:delete)
    ActiveStorage::Attachment.delete_all
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Blob.delete_all
  end

  def create_users!
    User::ROLES.keys.map(&:to_s).index_with do |role|
      User.create!(
        name: role,
        email: "#{role}@#{role}.com",
        password: "#{role}#{role}",
        password_confirmation: "#{role}#{role}",
        role:
      )
    end
  end

  def create_metadata!(admin)
    METADATA_TYPE_NAMES.each_with_index.to_h do |name, index|
      type = MetadataType.create!(
        name:,
        order: index + 1,
        access_level: User.roles.fetch("guest"),
        user: admin
      )
      values = metadata_names_for(name).map do |value_name|
        type.metadata.create!(name: value_name, under_review: false, user: admin)
      end

      [ name, { type:, values:, values_by_name: values.index_by(&:name) } ]
    end
  end

  def metadata_names_for(type_name)
    case type_name
    when "Topic"
      FOLDER_TREE.values.flatten + ADDITIONAL_TOPICS
    when "Audience"
      AUDIENCE_GROUPS.product(AUDIENCE_CONTEXTS).map { |group, context| "#{context} #{group}" }
    when "Region"
      REGIONS.product(REGION_CONTEXTS).map { |region, context| "#{context} #{region}" }
    when "Language"
      LANGUAGES
    when "Publisher"
      Array.new(VALUES_PER_METADATA_TYPE) do |index|
        "#{Faker::Company.name} #{format('%02d', index + 1)}"
      end
    end
  end

  def create_contents!(admin, metadata)
    contents_by_topic = {}
    content_number = 0

    FOLDER_TREE.values.flatten.each_with_index do |topic_name, topic_index|
      topic_count = topic_index < 10 ? 6 : 5
      contents_by_topic[topic_name] = Array.new(topic_count) do |index|
        content_number += 1
        create_content!(
          admin:,
          metadata:,
          content_number:,
          topic_name:,
          topic_sequence: index + 1
        )
      end
    end

    raise "Expected #{CONTENT_COUNT} contents, created #{content_number}" unless content_number == CONTENT_COUNT

    contents_by_topic
  end

  def create_content!(admin:, metadata:, content_number:, topic_name:, topic_sequence:)
    title_fragment = Faker::Lorem.sentence(word_count: 4).delete_suffix(".")
    title = format("%03d - %s: %s", content_number, topic_name, title_fragment)
    description = Faker::Lorem.paragraph(sentence_count: 3)
    content = Content.new(
      user: admin,
      title:,
      display_title: "#{topic_name} Resource #{topic_sequence}",
      description:,
      year_of_publication: 2000 + (content_number % 26),
      additional_notes: content_number % 4
    )
    content.file.attach(
      io: StringIO.new(pdf_bytes(title:, description:)),
      filename: format("demo-health-resource-%03d.pdf", content_number),
      content_type: "application/pdf"
    )
    content.save!

    metadata.each_value do |metadata_group|
      values = selected_metadata_values(
        metadata_group:,
        content_number:,
        topic_name:
      )
      values.each { |value| ContentMetadatum.create!(content:, metadata: value) }
    end

    content
  end

  def selected_metadata_values(metadata_group:, content_number:, topic_name:)
    values = metadata_group.fetch(:values)
    return values.rotate(content_number % values.length).first(VALUES_PER_CONTENT_AND_TYPE) unless metadata_group.fetch(:type).name == "Topic"

    primary = metadata_group.fetch(:values_by_name).fetch(topic_name)
    remaining = values.reject { |value| value == primary }
    [ primary, *remaining.rotate(content_number % remaining.length).first(VALUES_PER_CONTENT_AND_TYPE - 1) ]
  end

  def create_shelf!(admin, contents_by_topic)
    shelf = Shelf.create!(name: "Emergency Care Essentials", user: admin)
    related_contents = contents_by_topic.fetch("First Aid") + contents_by_topic.fetch("Injury Response").first(4)
    related_contents.each { |content| ShelfContent.create!(shelf:, content:) }
    ActiveShelf.activate!(user: admin, shelf:)
    shelf
  end

  def create_library!(admin, contents_by_topic)
    logo = create_library_asset!(admin)
    library = Library.create!(name: "Community Health Demonstration Library", user: admin)
    library_version = library.current_version

    FOLDER_TREE.each do |root_name, child_names|
      root = LibraryFolder.create!(name: root_name, library:, library_version:, user: admin, logo:)
      child_names.each do |child_name|
        child = LibraryFolder.create!(name: child_name, library:, library_version:, parent_folder: root, user: admin)
        contents_by_topic.fetch(child_name).each do |content|
          LibraryFolderContent.create!(library_folder: child, library_version:, content:)
        end
      end
    end

    library
  end

  def create_library_asset!(admin)
    asset = LibraryAsset.new(name: "Community Health Folder Logo", language: "English", user: admin)
    image_path = Rails.root.join("db/demo_assets/community_health_logo.png")
    design_path = Rails.root.join("db/demo_assets/community_health_logo.zip")

    File.open(image_path, "rb") do |image|
      File.open(design_path, "rb") do |design_files|
        asset.image.attach(io: image, filename: image_path.basename.to_s, content_type: "image/png")
        asset.design_files.attach(io: design_files, filename: design_path.basename.to_s, content_type: "application/zip")
        asset.save!
      end
    end

    asset
  end

  def pdf_bytes(title:, description:)
    text_lines = [ title, *description.scan(/.{1,76}(?:\s+|\z)/).map(&:strip) ].first(8)
    commands = [ "BT", "/F1 12 Tf", "72 720 Td" ]
    text_lines.each_with_index do |line, index|
      commands << "0 -18 Td" unless index.zero?
      commands << "(#{escape_pdf_text(line)}) Tj"
    end
    commands << "ET"
    stream = commands.join("\n")
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
      "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    pdf = "%PDF-1.4\n".b
    offsets = objects.each_with_index.map do |object, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
      offset
    end
    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.length + 1}\n"
    pdf << "0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\n"
    pdf << "startxref\n#{xref_offset}\n%%EOF\n"
  end

  def escape_pdf_text(text)
    text.encode("ASCII", invalid: :replace, undef: :replace, replace: "?")
      .gsub(/[\\()]/) { |character| "\\#{character}" }
  end

  def print_summary(users:, shelf:, library:)
    output.puts "Created development demo data:"
    output.puts "  #{users.length} users"
    output.puts "  #{MetadataType.count} metadata types and #{Metadatum.count} metadata values"
    output.puts "  #{Content.count} contents"
    output.puts "  Shelf: #{shelf.name} (#{shelf.contents.count} contents)"
    output.puts "  Library: #{library.name} (#{library.current_version.library_folders.roots.count} root folders)"
    output.puts "Demo credentials: role@role.com / rolerole"
  end
end
