require "test_helper"

class LibraryFolderOperations::PlaceContentsTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Health Library", user: users(:one))
    @library_version = @library.current_version
    @folder = @library_version.library_folders.create!(
      library: @library,
      name: "Destination",
      user: users(:one),
      logo: library_assets(:one)
    )
  end

  test "adds current-version manifests before current-version placements" do
    assert_difference("LibraryVersionContent.count", 2) do
      assert_difference("LibraryFolderContent.count", 2) do
        @result = LibraryFolderOperations::PlaceContents.call(
          library: @library,
          folder_id: @folder.id,
          content_ids: [ contents(:one).id, contents(:two).id ]
        )
      end
    end

    assert_equal :added, @result.status
    assert_equal [ contents(:one).id, contents(:two).id ], @result.missing_content_ids
    assert_empty @result.existing_content_ids
    assert_equal @result.missing_content_ids, @result.added_content_ids
    assert @folder.library_folder_contents.all? { |placement|
      placement.library_version_id == @library_version.id
    }
    assert_equal [ contents(:one).id, contents(:two).id ].sort,
      @library_version.library_version_contents.pluck(:content_id).sort
  end

  test "reports existing placements and adds only missing content" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @folder.id,
      content_ids: [ contents(:one).id ]
    )

    assert_difference("LibraryVersionContent.count", 1) do
      assert_difference("LibraryFolderContent.count", 1) do
        @result = LibraryFolderOperations::PlaceContents.call(
          library: @library,
          folder_id: @folder.id,
          content_ids: [ contents(:one).id, contents(:two).id ]
        )
      end
    end

    assert_equal :partially_added, @result.status
    assert_equal [ contents(:two).id ], @result.missing_content_ids
    assert_equal [ contents(:one).id ], @result.existing_content_ids
    assert @result.some_skipped?
    refute @result.none_added?
  end

  test "reports when every placement already exists" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @folder.id,
      content_ids: [ contents(:one).id ]
    )

    assert_no_difference("LibraryVersionContent.count") do
      assert_no_difference("LibraryFolderContent.count") do
        @result = LibraryFolderOperations::PlaceContents.call(
          library: @library,
          folder_id: @folder.id,
          content_ids: [ contents(:one).id ]
        )
      end
    end

    assert_equal :already_present, @result.status
    assert @result.none_added?
    assert @result.some_skipped?
  end

  test "rejects a destination outside the current version" do
    other_library = Library.create!(name: "Other Library", user: users(:one))
    other_folder = other_library.current_version.library_folders.create!(
      library: other_library,
      name: "Other Destination",
      user: users(:one),
      logo: library_assets(:one)
    )

    assert_no_difference([ "LibraryVersionContent.count", "LibraryFolderContent.count" ]) do
      assert_raises(ActiveRecord::RecordNotFound) do
        LibraryFolderOperations::PlaceContents.call(
          library: @library,
          folder_id: other_folder.id,
          content_ids: [ contents(:one).id ]
        )
      end
    end
  end

  test "rejects writes when the current version is locked" do
    @library_version.update_column(:locked_at, Time.current)

    assert_no_difference([ "LibraryVersionContent.count", "LibraryFolderContent.count" ]) do
      assert_raises(LibraryFolderOperations::Selection::InvalidSelection) do
        LibraryFolderOperations::PlaceContents.call(
          library: @library,
          folder_id: @folder.id,
          content_ids: [ contents(:one).id ]
        )
      end
    end
  end
end
