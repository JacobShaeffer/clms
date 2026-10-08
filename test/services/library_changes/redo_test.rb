require "test_helper"

class LibraryChanges::RedoTest < ActiveSupport::TestCase
  setup do
    @editor = users(:one)
    @editor.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    @library = Library.create!(name: "Redo Library", user: @editor)
    @version = @library.current_version
    @root = folder("Root")
    @destination = folder("Destination")
  end

  test "redo restores an entire cascade in place with original authors dates and dependencies" do
    child, creation = recorded_folder("Child", parent: @root)
    additions = place(child, [ contents(:one).id, contents(:two).id ])
    moves = LibraryFolderOperations::Move.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ child.id ], content_ids: [], destination_folder_id: @destination.id).recorded_changes
    ids = additions.map { |change| change.details["placement_id"] }
    dependents = additions + moves
    originals = [ creation, *dependents ].to_h do |change|
      [ change.id, change.attributes.except("updated_at") ]
    end
    original_targets = LibraryChangeTarget.where(library_change_id: originals.keys).order(:id).map(&:attributes)
    original_dependencies = LibraryChangeDependency.where(library_change_id: originals.keys).order(:id).map(&:attributes)
    LibraryChanges::CascadeUndo.call(change: creation, user: @editor, confirmed_dependent_ids: dependents.map(&:id))
    refute LibraryFolder.exists?(child.id)
    assert_equal 1, [ creation, *dependents ].map { |change| change.reload.undo_group_key }.uniq.length

    redone = nil
    assert_no_difference([ "LibraryChange.count", "LibraryChangeTarget.count", "LibraryChangeDependency.count" ]) do
      redone = replay(creation, user: @admin)
    end

    assert_equal 4, redone.length
    assert_equal @destination.id, LibraryFolder.find(child.id).parent_folder_id
    assert_equal ids.sort, child.library_folder_contents.ids.sort
    assert_equal originals.keys, redone.map(&:id)
    redone.each do |change|
      assert_equal originals.fetch(change.id).merge("replay_generation" => 1), change.attributes.except("updated_at")
      assert_empty LibraryChanges::Redo.group(change)
    end
    assert_equal original_targets, LibraryChangeTarget.where(library_change_id: originals.keys).order(:id).map(&:attributes)
    assert_equal original_dependencies, LibraryChangeDependency.where(library_change_id: originals.keys).order(:id).map(&:attributes)
    assert_includes redone[1].prerequisites, redone.first
    assert [ creation, *dependents ].none? { |change| change.reload.undone? }
    assert_raises(LibraryChanges::InvalidUndo) { replay(creation) }
  end

  test "repeated undo and redo preserve the original records and prerequisites" do
    child, creation = recorded_folder("Child", parent: @root)
    addition = place(child, [ contents(:one).id ]).first
    original_ids = [ creation.id, addition.id ]
    3.times do |cycle|
      LibraryChanges::Undo.call(change: addition, user: @editor)
      LibraryChanges::Undo.call(change: creation, user: @editor)
      creation = replay(creation).first
      addition = replay(addition).first
      assert_equal child.id, creation.details["folder_id"]
      assert_includes addition.prerequisites, creation
      assert_equal original_ids, [ creation.id, addition.id ]
      assert_equal cycle + 1, creation.replay_generation
      assert_equal cycle + 1, addition.replay_generation
      assert_equal 2, @version.library_changes.count
    end
    assert_equal 1, child.library_folder_contents.count
  end

  test "redo rejects confirmation from an earlier undo of the same records" do
    addition = place(@root, [ contents(:one).id ]).first
    LibraryChanges::Undo.call(change: addition, user: @editor)
    old_group = addition.undo_group_key
    replay(addition)
    LibraryChanges::Undo.call(change: addition, user: @editor)

    assert_no_difference([ "LibraryFolderContent.count", "LibraryChange.count" ]) do
      assert_raises(LibraryChanges::InvalidUndo) do
        LibraryChanges::Redo.call(change: addition, user: @editor, confirmed_change_ids: [ addition.id ],
          confirmed_undo_group_key: old_group)
      end
    end
    assert_predicate addition.reload, :undone?
    replay(addition)
    assert_equal 1, @root.library_folder_contents.count
  end

  test "redo duplicates the saved tree and placements rather than copying a changed source" do
    child = folder("Original", parent: @root)
    nested = folder("Nested", parent: child)
    LibraryFolderContent.create!(library_folder: nested, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @root, content: contents(:two))
    changes = LibraryFolderOperations::Duplicate.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ child.id ], content_ids: [ contents(:two).id ], destination_folder_id: @destination.id).recorded_changes
    tree = changes.find(&:duplicate_folder?)
    copied_ids = tree.details["folder_ids"]
    placement_ids = tree.details["placement_ids"] + changes.select(&:duplicate_content?).map { |change| change.details["placement_id"] }
    undo_batch(changes)
    child.update!(name: "Renamed source")
    redone = replay(changes.first)
    assert_equal 2, redone.length
    assert_equal copied_ids.sort, @destination.child_folders.first.then { |root| [ root.id, *root.child_folders.ids ] }.sort
    assert_equal "Original", LibraryFolder.find(tree.details["root_folder_id"]).name
    assert_equal placement_ids.sort, @version.library_folder_contents.where(id: placement_ids).ids.sort
  end

  test "redo removes a restored tree and content without losing their saved identities" do
    child = folder("Removed", parent: @root)
    nested = folder("Nested", parent: child)
    LibraryFolderContent.create!(library_folder: nested, content: contents(:one))
    LibraryFolderContent.create!(library_folder: @root, content: contents(:two))
    changes = LibraryFolderOperations::Remove.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ child.id ], content_ids: [ contents(:two).id ]).recorded_changes
    undo_batch(changes)
    assert LibraryFolder.exists?(nested.id)
    redone = replay(changes.first)
    refute LibraryFolder.exists?(child.id)
    refute LibraryFolder.exists?(nested.id)
    assert_empty @version.library_folder_contents.reload
    undo_batch(redone)
    assert LibraryFolder.exists?(nested.id)
    assert_equal 2, @version.library_folder_contents.count
  end

  test "redo preserves both source and destination identities for content moves including merges" do
    [ false, true ].each do |merge|
      source = folder("Source #{merge}")
      destination = folder("Destination #{merge}")
      source_placement = LibraryFolderContent.create!(library_folder: source, content: contents(:one))
      existing = LibraryFolderContent.create!(library_folder: destination, content: contents(:one)) if merge
      change = LibraryFolderOperations::Move.call(library: @library, user: @editor,
        source_folder_id: source.id, folder_ids: [], content_ids: [ contents(:one).id ], destination_folder_id: destination.id).recorded_changes.first
      destination_id = change.details["destination_placement_id"]
      LibraryChanges::Undo.call(change:, user: @editor)
      assert LibraryFolderContent.exists?(source_placement.id)
      replacement = replay(change).first
      refute LibraryFolderContent.exists?(source_placement.id)
      assert LibraryFolderContent.exists?(destination_id)
      assert_equal existing.id, destination_id if merge
      LibraryChanges::Undo.call(change: replacement, user: @editor)
      assert LibraryFolderContent.exists?(source_placement.id)
    end
  end

  test "foreign dependent changes block batch undo even for admins" do
    child, creation = recorded_folder("Child", parent: @root, user: @admin)
    place(child, [ contents(:one).id ], user: @editor)
    assert_raises(LibraryChanges::InvalidUndo) { undo_batch([ creation ], user: @admin) }
    assert LibraryFolder.exists?(child.id)
    refute_predicate creation.reload, :undone?
  end

  test "later edits deep inside a moved folder block undo" do
    child = folder("Child", parent: @root)
    nested = folder("Nested", parent: child)
    move = LibraryFolderOperations::Move.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ child.id ], content_ids: [], destination_folder_id: @destination.id).recorded_changes.first
    later = place(nested, [ contents(:one).id ], user: @admin).first
    assert_includes later.prerequisites, move
    assert_raises(LibraryChanges::InvalidUndo) { undo_batch([ move ]) }
    assert_equal @destination.id, child.reload.parent_folder_id
  end

  test "unrelated foreign edits allow undo and redo" do
    addition = place(@root, [ contents(:one).id ]).first
    place(@destination, [ contents(:two).id ], user: @admin)
    undo_batch([ addition ])
    assert_difference("LibraryFolderContent.count") { replay(addition) }
    assert @destination.library_folder_contents.exists?(content: contents(:two))
  end

  test "new children or placements block removal redo without any partial changes" do
    first = folder("First", parent: @root)
    second = folder("Second", parent: @root)
    changes = LibraryFolderOperations::Remove.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ first.id, second.id ], content_ids: []).recorded_changes
    undo_batch(changes)
    folder("Foreign child", parent: second, user: @admin)
    assert_no_difference([ "LibraryFolder.count", "LibraryChange.count" ]) do
      assert_raises(LibraryChanges::InvalidUndo) { replay(changes.first) }
    end
    assert LibraryFolder.exists?(first.id)
    assert LibraryFolder.exists?(second.id)
  end

  test "moving a required container after undo blocks redo" do
    addition = place(@root, [ contents(:one).id ]).first
    undo_batch([ addition ])
    LibraryFolderOperations::Move.call(library: @library, user: @admin,
      source_folder_id: nil, folder_ids: [ @root.id ], content_ids: [], destination_folder_id: @destination.id)
    assert_raises(LibraryChanges::InvalidUndo) { replay(addition) }
    refute @root.library_folder_contents.exists?(content: contents(:one))
    assert_equal @destination.id, @root.reload.parent_folder_id
  end

  test "redo refuses missing prerequisites stale confirmation locked versions and another editor" do
    child, creation = recorded_folder("Child", parent: @root)
    addition = place(child, [ contents(:one).id ]).first
    LibraryChanges::Undo.call(change: addition, user: @editor)
    LibraryChanges::Undo.call(change: creation, user: @editor)
    assert_raises(LibraryChanges::InvalidUndo) { replay(addition) }
    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Redo.call(change: creation, user: @editor, confirmed_change_ids: [])
    end
    @admin.update!(role: :intern_plus)
    assert_raises(LibraryChanges::InvalidUndo) { replay(creation, user: @admin) }
    @admin.update!(role: :admin)
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @admin)
    assert_raises(LibraryChanges::InvalidUndo) { replay(creation, user: @admin) }
  end

  test "redo restores a root folder's logo ownership and creation time" do
    root, creation = recorded_folder("Recorded root", parent: nil)
    created_at = root.created_at
    logo_id = root.logo_id
    LibraryChanges::Undo.call(change: creation, user: @editor)
    replay(creation, user: @admin)
    restored = LibraryFolder.find(root.id)
    assert_equal created_at, restored.created_at
    assert_equal @editor.id, restored.user_id
    assert_equal logo_id, restored.logo_id
    assert_nil restored.parent_folder_id
  end

  test "a failed member of a batch undo rolls back earlier members" do
    first = folder("First", parent: @root)
    second = folder("Second", parent: @root)
    changes = LibraryFolderOperations::Duplicate.call(library: @library, user: @editor,
      source_folder_id: @root.id, folder_ids: [ first.id, second.id ], content_ids: [], destination_folder_id: @destination.id).recorded_changes
    first_copy = LibraryFolder.find(changes.first.details["root_folder_id"])
    folder("Unrecorded child", parent: first_copy)
    assert_no_difference([ "LibraryFolder.count", "LibraryChange.count" ]) do
      assert_raises(LibraryChanges::InvalidUndo) { undo_batch(changes) }
    end
    assert changes.all? { |change| !change.reload.undone? && change.replay_snapshot.nil? }
    assert LibraryFolder.exists?(changes.last.details["root_folder_id"])
  end

  test "a model failure during redo rolls back every restored record and audit entry" do
    parent, creation = recorded_folder("Parent", parent: @root)
    recorded_folder("First", parent:)
    _, last = recorded_folder("Last", parent:)
    dependents = LibraryChanges::History.new(changes: @version.library_changes.includes(:dependency_links)).dependent_changes(creation)
    LibraryChanges::CascadeUndo.call(change: creation, user: @editor, confirmed_dependent_ids: dependents.map(&:id))
    snapshot = last.reload.replay_snapshot.deep_dup
    snapshot["applied"]["folders"][last.details["folder_id"].to_s]["name"] = ""
    last.update_columns(replay_snapshot: snapshot)
    assert_no_difference([ "LibraryFolder.count", "LibraryChange.count" ]) do
      assert_raises(LibraryChanges::InvalidUndo) { replay(creation) }
    end
    refute LibraryFolder.exists?(parent.id)
    assert_empty @version.library_changes.where.not(redo_of_id: nil)
    assert [ creation, *dependents ].all? { |record| record.reload.undone? && record.replay_generation.zero? && record.replay_snapshot.present? }
  end

  private

  def folder(name, parent: nil, user: @editor)
    @version.library_folders.create!(name:, library: @library, parent_folder: parent, user:, logo: (library_assets(:one) unless parent))
  end

  def recorded_folder(name, parent:, user: @editor)
    record = folder(name, parent:, user:)
    change = LibraryChanges::Recorder.call(library_version: @version, user:, action_type: :add_folder,
      details: { folder_id: record.id, parent_folder_id: parent&.id, logo_id: record.logo_id },
      targets: [ { target_kind: :folder, target_id: record.id, folder_id: record.id,
        resource_key: LibraryChanges::Recorder.folder_key(record), effect: :new, direct: true, label: name } ],
      required_folder_ids: [ parent&.id ].compact)
    [ record, change ]
  end

  def place(folder, ids, user: @editor)
    LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: folder.id, content_ids: ids, user:).recorded_changes
  end

  def undo_batch(changes, user: @editor)
    LibraryChanges::UndoBatch.call(changes:, user:, library: @library)
  end

  def replay(change, user: @editor)
    change.reload
    LibraryChanges::Redo.call(change:, user:, confirmed_change_ids: LibraryChanges::Redo.group(change).map(&:id))
  end
end
