require "test_helper"

class Contents::PermanentlyDeleteTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :admin)
    @content = build_content!
  end

  test "removes content and every editable and locked version reference" do
    shelf = @user.shelves.create!(name: "Purge shelf")
    shelf.contents << @content
    @content.metadata << Metadatum.first

    library = Library.create!(name: "Purge Library", user: @user)
    folder = library.current_version.library_folders.create!(
      library:,
      name: "Purge Folder",
      user: @user,
      logo: library_assets(:one)
    )
    LibraryFolderOperations::PlaceContents.call(
      library:,
      folder_id: folder.id,
      content_ids: [ @content.id ],
      user: @user
    )
    content_change = library.current_version.library_changes.add_content.last

    LibraryVersions::Create.call(library:, version_number: "2.0", user: @user)

    assert_equal 2, LibraryFolderContent.where(content_id: @content.id).count
    assert_equal 2, LibraryVersionContent.where(content_id: @content.id).count
    attachment_id = @content.file_attachment.id
    @content.trash!(comment: "Permanent")

    Contents::PermanentlyDelete.call(content: @content)

    refute Content.exists?(@content.id)
    refute ShelfContent.exists?(content_id: @content.id)
    refute ContentMetadatum.exists?(content_id: @content.id)
    refute LibraryFolderContent.exists?(content_id: @content.id)
    refute LibraryVersionContent.exists?(content_id: @content.id)
    refute LibraryChangeTarget.exists?(content_id: @content.id)
    refute LibraryChange.exists?(content_change.id)
    refute ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "scrubs content from mixed folder history without breaking folder undo" do
    library = Library.create!(name: "Mixed History Library", user: @user)
    folder = library.current_version.library_folders.create!(
      library:,
      name: "Removed Folder",
      user: @user,
      logo: library_assets(:one)
    )
    placement = LibraryFolderOperations::PlaceContents.call(
      library:,
      folder_id: folder.id,
      content_ids: [ @content.id ],
      user: @user
    ).added_placements.first

    LibraryFolderOperations::Remove.call(
      library:,
      source_folder_id: nil,
      folder_ids: [ folder.id ],
      content_ids: [],
      user: @user
    )
    folder_change = library.current_version.library_changes.remove_folder.last
    content_change_ids = library.current_version.library_changes
      .joins(:library_change_targets)
      .where(library_change_targets: { content_id: @content.id })
      .where(action_type: Contents::PermanentlyDelete::CONTENT_ONLY_ACTIONS)
      .ids

    assert_includes folder_change.details.fetch("content_ids"), @content.id
    assert_includes folder_change.details.fetch("placement_ids"), placement.id
    assert folder_change.details.fetch("placement_snapshots").any? { |row| row["content_id"] == @content.id }

    @content.trash!
    Contents::PermanentlyDelete.call(content: @content)

    folder_change.reload
    assert_empty folder_change.library_change_targets.where(content_id: @content.id)
    assert_empty folder_change.details.fetch("content_ids")
    assert_empty folder_change.details.fetch("placement_ids")
    assert_empty folder_change.details.fetch("placement_snapshots")
    assert_empty LibraryChange.where(id: content_change_ids)
    assert_empty LibraryChangeDependency.where(library_change_id: content_change_ids)
    assert_empty LibraryChangeDependency.where(prerequisite_change_id: content_change_ids)

    LibraryChanges::Undo.call(change: folder_change, user: @user)

    assert LibraryFolder.exists?(folder.id)
    refute LibraryFolderContent.exists?(content_id: @content.id)
  end

  test "refuses to delete active content" do
    assert_raises(ArgumentError) do
      Contents::PermanentlyDelete.call(content: @content)
    end

    assert Content.exists?(@content.id)
  end

  test "scrubs replay snapshots after redo without resurrecting content" do
    library = Library.create!(name: "Replay Purge", user: @user)
    root = library.current_version.library_folders.create!(name: "Root", user: @user, logo: library_assets(:one))
    child = library.current_version.library_folders.create!(name: "Child", parent_folder: root, user: @user)
    addition = LibraryFolderOperations::PlaceContents.call(library:, folder_id: child.id,
      content_ids: [ @content.id ], user: @user).recorded_changes.first
    LibraryChanges::Undo.call(change: addition, user: @user)
    redone_addition = LibraryChanges::Redo.call(change: addition, user: @user, confirmed_change_ids: [ addition.id ]).first
    assert_equal addition.id, redone_addition.id
    removal = LibraryFolderOperations::Remove.call(library:, source_folder_id: root.id,
      folder_ids: [ child.id ], content_ids: [], user: @user).recorded_changes.first
    LibraryChanges::Undo.call(change: removal, user: @user)
    @content.trash!
    Contents::PermanentlyDelete.call(content: @content)

    refute LibraryChange.exists?(addition.id)
    removal.reload.replay_snapshot.each_value do |state|
      assert_empty state["placements"]
      assert_empty state["placement_keys"]
      assert state["contents"].values.all?(&:empty?)
    end
    redone = LibraryChanges::Redo.call(change: removal, user: @user, confirmed_change_ids: [ removal.id ]).first
    refute LibraryFolder.exists?(child.id)
    LibraryChanges::Undo.call(change: redone, user: @user)
    assert LibraryFolder.exists?(child.id)
    refute LibraryFolderContent.exists?(content_id: @content.id)
  end

  private

  def build_content!
    token = SecureRandom.hex(4)
    Content.new(
      user: @user,
      title: "Purge content #{token}",
      display_title: "Purge content",
      description: "Content used to verify permanent deletion."
    ).tap do |content|
      content.file.attach(
        io: StringIO.new("purge bytes #{token}"),
        filename: "purge-#{token}.pdf",
        content_type: "application/pdf"
      )
      content.save!
    end
  end
end
