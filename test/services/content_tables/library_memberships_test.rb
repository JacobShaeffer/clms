require "test_helper"

class ContentTables::LibraryMembershipsTest < ActiveSupport::TestCase
  setup do
    @first = contents(:one)
    @second = contents(:two)
    @alpha = Library.create!(name: "alpha Library", user: users(:one))
    @zulu = Library.create!(name: "Zulu Library", user: users(:one))
    @alpha_root = @alpha.current_version.library_folders.create!(name: "Guides", user: users(:one))
    @alpha_child = @alpha.current_version.library_folders.create!(name: "First Aid", user: users(:one), parent_folder: @alpha_root)
    @zulu_root = @zulu.current_version.library_folders.create!(name: "Guides", user: users(:one))
    [ @alpha_root, @alpha_child, @zulu_root ].each do |folder|
      LibraryFolderContent.create!(library_folder: folder, content: @first)
    end
  end

  test "groups multiple placements into one alphabetically ordered badge per library" do
    memberships = build_memberships

    assert_equal [ @alpha.id, @zulu.id ], memberships.libraries_for(@first).map(&:id)
    assert_equal [ @alpha.name, @zulu.name ], memberships.libraries_for(@first).map(&:name)
    assert_empty memberships.libraries_for(@second)
  end

  test "only includes libraries in the authorized scope" do
    memberships = build_memberships(library_scope: Library.where(id: @zulu.id))

    assert_equal [ @zulu.id ], memberships.libraries_for(@first).map(&:id)
  end

  test "historical placements do not count after content is removed from the current version" do
    locked_version = @alpha.current_version
    LibraryVersions::Create.call(library: @alpha, version_number: "2.0", user: users(:one))
    @alpha.reload.current_version.library_folder_contents.where(content: @first).each(&:destroy!)

    assert locked_version.library_folder_contents.exists?(content: @first)
    assert_equal [ @zulu.id ], build_memberships.libraries_for(@first).map(&:id)
  end

  test "membership loading uses one query for any nonempty page and none for an empty page" do
    assert_queries_count(1) { build_memberships(content_ids: [ @first.id ]) }
    assert_queries_count(1) { build_memberships(content_ids: [ @first.id, @second.id ]) }
    assert_no_queries { build_memberships(content_ids: []) }
  end

  private

  def build_memberships(library_scope: Library.all, content_ids: [ @first.id, @second.id ])
    ContentTables::LibraryMemberships.new(library_scope:, content_ids:)
  end
end
