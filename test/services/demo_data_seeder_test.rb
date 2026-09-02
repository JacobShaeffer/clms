require "test_helper"
require Rails.root.join("db/demo_data_seeder").to_s

class DemoDataSeederTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  teardown do
    ActiveStorage::Blob.find_each { |blob| blob.service.delete(blob.key) }
  end

  test "rebuilds the complete development demonstration dataset" do
    User.create!(name: "Existing user", email: "existing@example.com", password: "password")

    output = StringIO.new
    DemoDataSeeder.call(output:)

    refute User.exists?(email: "existing@example.com")
    assert_users
    assert_metadata
    assert_contents
    assert_shelf
    assert_library
    assert_includes output.string, "Created development demo data:"
  end

  private

  def assert_users
    assert_equal User::ROLES.length, User.count
    assert_equal User::ROLES.keys.map(&:to_s).sort, User.all.map(&:role).sort

    User::ROLES.each_key do |role|
      user = User.find_by!(email: "#{role}@#{role}.com")
      assert_equal role.to_s, user.name
      assert_equal role.to_s, user.role
      assert user.valid_password?("#{role}#{role}")
    end
  end

  def assert_metadata
    assert_equal DemoDataSeeder::METADATA_TYPE_NAMES,
      MetadataType.order(:order).pluck(:name)
    assert_equal [ DemoDataSeeder::VALUES_PER_METADATA_TYPE ],
      MetadataType.order(:order).map { |type| type.metadata.count }.uniq
    assert_equal 0, Metadatum.where(under_review: true).count
  end

  def assert_contents
    assert_equal DemoDataSeeder::CONTENT_COUNT, Content.count
    assert_equal DemoDataSeeder::CONTENT_COUNT, Content.joins(:file_attachment).count

    blobs = Content.includes(file_attachment: :blob).map { |content| content.file.blob }
    assert_equal DemoDataSeeder::CONTENT_COUNT, blobs.map { |blob| blob.filename.to_s.downcase }.uniq.length
    assert_equal DemoDataSeeder::CONTENT_COUNT, blobs.map(&:checksum).uniq.length
    assert blobs.all? { |blob| blob.download.start_with?("%PDF-1.4") }

    metadata_counts = ContentMetadatum.joins(:metadata)
      .group(:content_id, :metadata_type_id)
      .count
    assert_equal DemoDataSeeder::CONTENT_COUNT * DemoDataSeeder::METADATA_TYPE_NAMES.length,
      metadata_counts.length
    assert_equal [ DemoDataSeeder::VALUES_PER_CONTENT_AND_TYPE ], metadata_counts.values.uniq
  end

  def assert_shelf
    assert_equal 1, Shelf.count
    shelf = Shelf.find_by!(name: "Emergency Care Essentials")
    assert_equal 10, shelf.contents.count
    assert_equal shelf, ActiveShelf.find_by!(user: User.find_by!(role: :admin)).shelf

    topic_names = shelf.contents.joins(metadata: :metadata_type)
      .where(metadata_types: { name: "Topic" })
      .distinct
      .pluck("metadata.name")
    assert_includes topic_names, "First Aid"
    assert_includes topic_names, "Injury Response"
    assert shelf.contents.includes(metadata: :metadata_type).all? do |content|
      content.metadata.any? do |value|
        value.metadata_type.name == "Topic" && value.name.in?([ "First Aid", "Injury Response" ])
      end
    end
  end

  def assert_library
    assert_equal 1, Library.count
    library = Library.find_by!(name: "Community Health Demonstration Library")
    assert_equal "1.0", library.current_version.version_number
    assert_predicate library.current_version, :editable?
    assert_equal 1, LibraryAsset.count

    logo = LibraryAsset.first
    assert logo.image.attached?
    assert logo.design_files.attached?
    assert_equal "\x89PNG\r\n\x1A\n".b, logo.image.download.first(8)
    assert_equal "PK\x05\x06".b, logo.design_files.download.first(4)

    roots = library.current_version.library_folders.roots.order(:id)
    assert_equal DemoDataSeeder::FOLDER_TREE.keys, roots.pluck(:name)
    assert roots.all? { |root| root.child_folders.count == 3 }

    child_folders = library.current_version.library_folders.where.not(parent_folder_id: nil)
    assert_equal 18, child_folders.count
    assert_equal [ 5, 6 ], child_folders.map { |folder| folder.contents.count }.uniq.sort
    assert_equal DemoDataSeeder::CONTENT_COUNT, library.current_version.library_folder_contents.count
    assert_equal DemoDataSeeder::CONTENT_COUNT,
      library.current_version.library_folder_contents.distinct.count(:content_id)
    assert_equal DemoDataSeeder::CONTENT_COUNT, library.current_version.library_version_contents.count
    assert library.current_version.library_version_contents.all? { |entry| entry.file_checksum.present? }

    topic_type = MetadataType.find_by!(name: "Topic")
    child_folders.includes(contents: :metadata).find_each do |folder|
      assert folder.contents.all? do |content|
        content.metadata.any? { |value| value.metadata_type_id == topic_type.id && value.name == folder.name }
      end
    end
  end
end
