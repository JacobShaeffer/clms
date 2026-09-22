require "test_helper"

class LibraryChanges::ResolveTest < ActiveSupport::TestCase
  setup do
    @editor = users(:one)
    @editor.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    @library = Library.create!(name: "Approval Library", user: @editor)
    @version = @library.current_version
    @root = create_folder!("Root")
  end

  test "records independent batch items as separately resolvable changes" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id, contents(:two).id ],
      user: @editor
    )

    changes = @version.library_changes.add_content.ordered.to_a
    assert_equal 2, changes.length
    assert_equal 1, changes.map(&:batch_key).uniq.length
    assert_empty changes.first.prerequisites
    assert_empty changes.second.prerequisites

    LibraryChanges::Approve.call(change: changes.first, user: @admin)
    LibraryChanges::Undo.call(change: changes.second, user: @editor)

    assert_predicate changes.first.reload, :approved?
    assert_predicate changes.second.reload, :undone?
    assert @root.library_folder_contents.exists?(content: contents(:one))
    refute @root.library_folder_contents.exists?(content: contents(:two))
  end

  test "approves a dependent chain from oldest to newest" do
    folder, folder_change = create_pending_folder!("Pending", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: folder.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    content_change = @version.library_changes.add_content.last

    assert_equal [ folder_change ], content_change.prerequisites.to_a
    error = assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change: content_change, user: @admin)
    end
    assert_match(/Approve Pending before/, error.message)

    LibraryChanges::Approve.call(change: folder_change, user: @admin)
    LibraryChanges::Approve.call(change: content_change, user: @admin)

    assert_predicate folder_change.reload, :approved?
    assert_predicate content_change.reload, :approved?
  end

  test "undoes a dependent chain from newest to oldest" do
    folder, folder_change = create_pending_folder!("Pending", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: folder.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    content_change = @version.library_changes.add_content.last

    error = assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Undo.call(change: folder_change, user: @editor)
    end
    assert_match(/Undo .* before undoing/, error.message)

    LibraryChanges::Undo.call(change: content_change, user: @editor)
    LibraryChanges::Undo.call(change: folder_change, user: @editor)

    refute LibraryFolder.exists?(folder.id)
    assert_predicate content_change.reload, :undone?
    assert_predicate folder_change.reload, :undone?
  end

  test "undoes and approves content removals" do
    placement = LibraryFolderContent.create!(library_folder: @root, content: contents(:one))
    remove_content!(placement)
    first_change = @version.library_changes.remove_content.last

    LibraryChanges::Undo.call(change: first_change, user: @editor)
    refute placement.reload.pending_removal?
    assert @version.library_version_contents.exists?(content: contents(:one))

    remove_content!(placement)
    second_change = @version.library_changes.remove_content.last
    LibraryChanges::Approve.call(change: second_change, user: @admin)

    refute LibraryFolderContent.exists?(placement.id)
    refute @version.library_version_contents.exists?(content: contents(:one))
    assert_predicate second_change.reload, :approved?
  end

  test "marks a removed folder tree and deletes it only after approval" do
    child = create_folder!("Child", parent_folder: @root)
    nested = create_folder!("Nested", parent_folder: child)
    placement = LibraryFolderContent.create!(library_folder: nested, content: contents(:one))

    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ child.id ],
      content_ids: [],
      user: @editor
    )
    change = @version.library_changes.remove_folder.last
    state = LibraryChanges::BrowserState.new(library_version: @version)

    assert_equal "Removed", state.badge_for_folder(child.reload)
    assert_equal "Parent Folder Removed", state.badge_for_folder(nested.reload)
    assert_equal "Parent Folder Removed", state.badge_for_placement(placement.reload)

    LibraryChanges::Approve.call(change:, user: @admin)

    refute LibraryFolder.exists?(child.id)
    refute LibraryFolder.exists?(nested.id)
    refute LibraryFolderContent.exists?(placement.id)
    refute @version.library_version_contents.exists?(content: contents(:one))
  end

  test "undoing folder removal restores the complete tombstoned tree" do
    child = create_folder!("Child", parent_folder: @root)
    nested = create_folder!("Nested", parent_folder: child)
    placement = LibraryFolderContent.create!(library_folder: nested, content: contents(:one))
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ child.id ],
      content_ids: [],
      user: @editor
    )
    change = @version.library_changes.remove_folder.last

    LibraryChanges::Undo.call(change:, user: @editor)

    refute child.reload.pending_removal?
    refute nested.reload.pending_removal?
    refute placement.reload.pending_removal?
    assert_predicate change.reload, :undone?
  end

  test "undoes folder and content moves" do
    destination = create_folder!("Destination")
    child = create_folder!("Child", parent_folder: @root)
    placement = LibraryFolderContent.create!(library_folder: @root, content: contents(:one))

    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ child.id ],
      content_ids: [ placement.content_id ],
      destination_folder_id: destination.id,
      user: @editor
    )
    content_change = @version.library_changes.move_content.last
    folder_change = @version.library_changes.move_folder.last

    LibraryChanges::Undo.call(change: content_change, user: @editor)
    LibraryChanges::Undo.call(change: folder_change, user: @editor)

    assert_equal @root, child.reload.parent_folder
    assert @root.library_folder_contents.exists?(content: contents(:one))
    refute destination.library_folder_contents.exists?(content: contents(:one))
  end

  test "undoes a duplicated folder as one change" do
    source = create_folder!("Source", parent_folder: @root)
    LibraryFolderContent.create!(library_folder: source, content: contents(:one))
    destination = create_folder!("Destination")

    LibraryFolderOperations::Duplicate.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ source.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    change = @version.library_changes.duplicate_folder.last
    copied_id = change.details.fetch("root_folder_id")

    LibraryChanges::Undo.call(change:, user: @editor)

    refute LibraryFolder.exists?(copied_id)
    assert LibraryFolder.exists?(source.id)
    assert_predicate change.reload, :undone?
  end

  test "approving a duplicated folder keeps its generated tree" do
    source = create_folder!("Source", parent_folder: @root)
    LibraryFolderContent.create!(library_folder: source, content: contents(:one))
    destination = create_folder!("Destination")
    LibraryFolderOperations::Duplicate.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ source.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    change = @version.library_changes.duplicate_folder.last

    LibraryChanges::Approve.call(change:, user: @admin)

    assert LibraryFolder.exists?(change.details.fetch("root_folder_id"))
    assert_predicate change.reload, :approved?
  end

  test "undoes and approves duplicated content placements" do
    source_placement = LibraryFolderContent.create!(
      library_folder: @root,
      content: contents(:one)
    )
    destination = create_folder!("Destination")

    duplicate_content!(source_placement, destination)
    first_change = @version.library_changes.duplicate_content.last
    LibraryChanges::Undo.call(change: first_change, user: @editor)

    refute destination.library_folder_contents.exists?(content: contents(:one))
    assert LibraryFolderContent.exists?(source_placement.id)

    duplicate_content!(source_placement, destination)
    second_change = @version.library_changes.duplicate_content.last
    LibraryChanges::Approve.call(change: second_change, user: @admin)

    assert destination.library_folder_contents.exists?(content: contents(:one))
    assert_predicate second_change.reload, :approved?
  end

  test "undoing a root folder move restores its logo" do
    destination = create_folder!("Destination")
    original_logo = @root.logo

    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ @root.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    change = @version.library_changes.move_folder.last

    assert_nil @root.reload.logo
    LibraryChanges::Undo.call(change:, user: @editor)

    assert_nil @root.reload.parent_folder
    assert_equal original_logo, @root.logo
  end

  test "folder removal waits for a pending move out of its subtree" do
    destination = create_folder!("Destination")
    child = create_folder!("Child", parent_folder: @root)
    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ child.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    move_change = @version.library_changes.move_folder.last

    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ @root.id ],
      content_ids: [],
      user: @editor
    )
    remove_change = @version.library_changes.remove_folder.last

    assert_includes remove_change.prerequisites, move_change
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change: remove_change, user: @admin)
    end

    LibraryChanges::Approve.call(change: move_change, user: @admin)
    LibraryChanges::Approve.call(change: remove_change, user: @admin)

    refute LibraryFolder.exists?(@root.id)
    assert_equal destination, child.reload.parent_folder
  end

  test "multi-prerequisite removal stays blocked until every prerequisite is approved" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id, contents(:two).id ],
      user: @editor
    )
    additions = @version.library_changes.add_content.ordered.to_a
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ @root.id ],
      content_ids: [],
      user: @editor
    )
    removal = @version.library_changes.remove_folder.last

    assert_equal additions, removal.prerequisites.ordered.to_a
    LibraryChanges::Approve.call(change: additions.first, user: @admin)
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change: removal, user: @admin)
    end

    LibraryChanges::Approve.call(change: additions.second, user: @admin)
    LibraryChanges::Approve.call(change: removal, user: @admin)
    assert_predicate removal.reload, :approved?
  end

  test "undoing chained moves restores stable placement identities" do
    second_folder = create_folder!("Second")
    third_folder = create_folder!("Third")
    source_placement = LibraryFolderContent.create!(
      library_folder: @root,
      content: contents(:one)
    )
    move_content!(source: @root, destination: second_folder)
    first_change = @version.library_changes.move_content.last
    first_destination_id = first_change.details.fetch("destination_placement_id")
    move_content!(source: second_folder, destination: third_folder)
    second_change = @version.library_changes.move_content.last

    LibraryChanges::Undo.call(change: second_change, user: @editor)

    restored_second = second_folder.library_folder_contents.find_by!(content: contents(:one))
    assert_equal first_destination_id, restored_second.id
    assert_equal "Moved", LibraryChanges::BrowserState.new(
      library_version: @version
    ).badge_for_placement(restored_second)

    LibraryChanges::Undo.call(change: first_change, user: @editor)
    assert_equal source_placement.id,
      @root.library_folder_contents.find_by!(content: contents(:one)).id
  end

  test "only the author or an admin can undo and only an admin can approve" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    change = @version.library_changes.last
    other_editor = User.create!(
      name: "Other Editor",
      email: "other-editor@example.com",
      password: "password",
      role: :intern_plus
    )

    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Undo.call(change:, user: other_editor)
    end
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change:, user: @editor)
    end
    @editor.update!(role: :intern)
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Undo.call(change:, user: @editor)
    end

    LibraryChanges::Approve.call(change:, user: @admin)
    assert_predicate change.reload, :approved?
    assert_equal @admin, change.resolved_by
  end

  test "admins can approve their own changes and undo another user's changes" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id ],
      user: @admin
    )
    admin_change = @version.library_changes.last
    LibraryChanges::Approve.call(change: admin_change, user: @admin)

    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:two).id ],
      user: @editor
    )
    editor_change = @version.library_changes.last
    LibraryChanges::Undo.call(change: editor_change, user: @admin)

    assert_predicate admin_change.reload, :approved?
    assert_predicate editor_change.reload, :undone?
    assert_equal @admin, admin_change.user
    assert_equal @admin, editor_change.resolved_by
  end

  test "approved and undone changes cannot be resolved again" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id, contents(:two).id ],
      user: @editor
    )
    approved_change, undone_change = @version.library_changes.ordered.to_a
    LibraryChanges::Approve.call(change: approved_change, user: @admin)
    LibraryChanges::Undo.call(change: undone_change, user: @editor)

    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change: approved_change, user: @admin)
    end
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Undo.call(change: approved_change, user: @admin)
    end
    assert_raises(LibraryChanges::InvalidResolution) do
      LibraryChanges::Approve.call(change: undone_change, user: @admin)
    end
  end

  private

  def create_folder!(name, parent_folder: nil)
    @version.library_folders.create!(
      library: @library,
      name:,
      parent_folder:,
      user: @editor,
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end

  def create_pending_folder!(name, parent_folder:)
    folder = create_folder!(name, parent_folder:)
    change = LibraryChanges::Recorder.call(
      library_version: @version,
      user: @editor,
      action_type: :add_folder,
      details: {
        folder_id: folder.id,
        parent_folder_id: parent_folder.id,
        logo_id: nil
      },
      targets: [ {
        target_kind: :folder,
        target_id: folder.id,
        folder_id: folder.id,
        resource_key: LibraryChanges::Recorder.folder_key(folder),
        effect: :new,
        direct: true,
        label: folder.name
      } ],
      required_folder_ids: [ parent_folder.id ]
    )
    [ folder, change ]
  end

  def remove_content!(placement)
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: placement.library_folder_id,
      folder_ids: [],
      content_ids: [ placement.content_id ],
      user: @editor
    )
  end

  def duplicate_content!(placement, destination)
    LibraryFolderOperations::Duplicate.call(
      library: @library,
      source_folder_id: placement.library_folder_id,
      folder_ids: [],
      content_ids: [ placement.content_id ],
      destination_folder_id: destination.id,
      user: @editor
    )
  end

  def move_content!(source:, destination:)
    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: source.id,
      folder_ids: [],
      content_ids: [ contents(:one).id ],
      destination_folder_id: destination.id,
      user: @editor
    )
  end
end
