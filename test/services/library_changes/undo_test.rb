require "test_helper"

class LibraryChanges::UndoTest < ActiveSupport::TestCase
  setup do
    @editor = users(:one)
    @editor.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    @library = Library.create!(name: "Undo Library", user: @editor)
    @version = @library.current_version
    @root = create_folder!("Root")
  end

  test "records batch items separately and allows either item to be undone" do
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

    LibraryChanges::Undo.call(change: changes.second, user: @editor)

    refute_predicate changes.first.reload, :undone?
    assert_predicate changes.second.reload, :undone?
    assert @root.library_folder_contents.exists?(content: contents(:one))
    refute @root.library_folder_contents.exists?(content: contents(:two))
  end

  test "undoes a dependent chain from newest to oldest" do
    folder, folder_change = create_recorded_folder!("Child", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: folder.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    content_change = @version.library_changes.add_content.last

    assert_equal [ folder_change ], content_change.prerequisites.to_a
    error = assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change: folder_change, user: @editor)
    end
    assert_match(/Undo .* before undoing/, error.message)

    LibraryChanges::Undo.call(change: content_change, user: @editor)
    LibraryChanges::Undo.call(change: folder_change, user: @editor)

    refute LibraryFolder.exists?(folder.id)
    assert_predicate content_change.reload, :undone?
    assert_predicate folder_change.reload, :undone?
  end

  test "content removal deletes immediately and undo restores its identity and manifest" do
    placement = LibraryFolderContent.create!(library_folder: @root, content: contents(:one))
    placement_id = placement.id
    created_at = placement.created_at

    remove_content!(placement)
    change = @version.library_changes.remove_content.last

    refute LibraryFolderContent.exists?(placement_id)
    refute @version.library_version_contents.exists?(content: contents(:one))
    assert_equal placement_id, change.details.dig("placement_snapshot", "id")

    LibraryChanges::Undo.call(change:, user: @editor)

    restored = @root.library_folder_contents.find_by!(content: contents(:one))
    assert_equal placement_id, restored.id
    assert_equal created_at, restored.created_at
    assert @version.library_version_contents.exists?(content: contents(:one))
    assert_predicate change.reload, :undone?
  end

  test "folder removal deletes immediately and undo restores the complete tree" do
    child = create_folder!("Child", parent_folder: @root)
    nested = create_folder!("Nested", parent_folder: child)
    placement = LibraryFolderContent.create!(library_folder: nested, content: contents(:one))
    child_id = child.id
    nested_id = nested.id
    placement_id = placement.id

    remove_folder!(child)
    change = @version.library_changes.remove_folder.last

    refute LibraryFolder.exists?(child_id)
    refute LibraryFolder.exists?(nested_id)
    refute LibraryFolderContent.exists?(placement_id)
    refute @version.library_version_contents.exists?(content: contents(:one))

    LibraryChanges::Undo.call(change:, user: @editor)

    restored_child = LibraryFolder.find(child_id)
    restored_nested = LibraryFolder.find(nested_id)
    restored_placement = LibraryFolderContent.find(placement_id)
    assert_equal @root, restored_child.parent_folder
    assert_equal restored_child, restored_nested.parent_folder
    assert_equal restored_nested, restored_placement.library_folder
    assert_equal contents(:one), restored_placement.content
    assert @version.library_version_contents.exists?(content: contents(:one))
    assert_predicate change.reload, :undone?
  end

  test "undoing root folder removal restores its ownership logo and timestamps" do
    root_id = @root.id
    logo = @root.logo
    created_at = @root.created_at

    remove_folder!(@root)
    change = @version.library_changes.remove_folder.last
    LibraryChanges::Undo.call(change:, user: @editor)

    restored = LibraryFolder.find(root_id)
    assert_equal @library, restored.library
    assert_equal @version, restored.library_version
    assert_equal @editor, restored.user
    assert_equal logo, restored.logo
    assert_equal created_at, restored.created_at
  end

  test "undoes folder and content moves" do
    destination = create_folder!("Destination")
    child = create_folder!("Child", parent_folder: @root)
    LibraryFolderContent.create!(library_folder: @root, content: contents(:one))

    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ child.id ],
      content_ids: [ contents(:one).id ],
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

  test "undoes duplicated folders and content placements" do
    source = create_folder!("Source", parent_folder: @root)
    source_placement = LibraryFolderContent.create!(library_folder: source, content: contents(:one))
    destination = create_folder!("Destination")

    LibraryFolderOperations::Duplicate.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ source.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    folder_change = @version.library_changes.duplicate_folder.last
    copied_id = folder_change.details.fetch("root_folder_id")

    LibraryChanges::Undo.call(change: folder_change, user: @editor)

    refute LibraryFolder.exists?(copied_id)
    assert LibraryFolder.exists?(source.id)

    duplicate_content!(source_placement, destination)
    content_change = @version.library_changes.duplicate_content.last
    LibraryChanges::Undo.call(change: content_change, user: @editor)

    refute destination.library_folder_contents.exists?(content: contents(:one))
    assert LibraryFolderContent.exists?(source_placement.id)
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

  test "re-adding removed content must be undone before restoring the removal" do
    placement = LibraryFolderContent.create!(library_folder: @root, content: contents(:one))
    original_id = placement.id
    remove_content!(placement)
    removal = @version.library_changes.remove_content.last

    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    addition = @version.library_changes.add_content.last

    assert_includes addition.prerequisites, removal
    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change: removal, user: @editor)
    end

    LibraryChanges::Undo.call(change: addition, user: @editor)
    LibraryChanges::Undo.call(change: removal, user: @editor)

    assert_equal original_id, @root.library_folder_contents.find_by!(content: contents(:one)).id
  end

  test "a later parent move must be undone before restoring a removed child" do
    child = create_folder!("Child", parent_folder: @root)
    child_id = child.id
    destination = create_folder!("Destination")
    remove_folder!(child)
    removal = @version.library_changes.remove_folder.last

    LibraryFolderOperations::Move.call(
      library: @library,
      source_folder_id: nil,
      folder_ids: [ @root.id ],
      content_ids: [],
      destination_folder_id: destination.id,
      user: @editor
    )
    move = @version.library_changes.move_folder.last

    assert_includes move.prerequisites, removal
    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change: removal, user: @editor)
    end

    LibraryChanges::Undo.call(change: move, user: @editor)
    LibraryChanges::Undo.call(change: removal, user: @editor)

    assert_equal @root, LibraryFolder.find(child_id).parent_folder
  end

  test "sibling removals from the same batch can be undone independently" do
    first = create_folder!("First", parent_folder: @root)
    second = create_folder!("Second", parent_folder: @root)

    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: @root.id,
      folder_ids: [ first.id, second.id ],
      content_ids: [],
      user: @editor
    )
    changes = @version.library_changes.remove_folder.ordered.to_a

    assert_equal 2, changes.length
    assert_empty changes.first.prerequisites
    assert_empty changes.second.prerequisites

    LibraryChanges::Undo.call(change: changes.first, user: @editor)

    assert LibraryFolder.exists?(first.id)
    refute LibraryFolder.exists?(second.id)
  end

  test "undoing chained moves restores stable placement identities" do
    second_folder = create_folder!("Second")
    third_folder = create_folder!("Third")
    source_placement = LibraryFolderContent.create!(library_folder: @root, content: contents(:one))
    move_content!(source: @root, destination: second_folder)
    first_change = @version.library_changes.move_content.last
    first_destination_id = first_change.details.fetch("destination_placement_id")
    move_content!(source: second_folder, destination: third_folder)
    second_change = @version.library_changes.move_content.last

    LibraryChanges::Undo.call(change: second_change, user: @editor)

    restored_second = second_folder.library_folder_contents.find_by!(content: contents(:one))
    assert_equal first_destination_id, restored_second.id

    LibraryChanges::Undo.call(change: first_change, user: @editor)
    assert_equal source_placement.id,
      @root.library_folder_contents.find_by!(content: contents(:one)).id
  end

  test "only the author or an admin can undo" do
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

    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change:, user: other_editor)
    end
    @editor.update!(role: :intern)
    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change:, user: @editor)
    end

    LibraryChanges::Undo.call(change:, user: @admin)

    assert_predicate change.reload, :undone?
    assert_equal @admin, change.undone_by
    assert change.undone_at.present?
  end

  test "an undone change cannot be undone again" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    change = @version.library_changes.last
    LibraryChanges::Undo.call(change:, user: @editor)

    error = assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change:, user: @admin)
    end
    assert_equal "This library change has already been undone.", error.message
  end

  test "changes in locked versions cannot be undone" do
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @root.id,
      content_ids: [ contents(:one).id ],
      user: @editor
    )
    change = @version.library_changes.last
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @admin)

    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::Undo.call(change:, user: @admin)
    end
  end

  test "cascade undo reverses branches and shared dependents once while retaining unrelated edits" do
    folder, root_change = create_recorded_folder!("Cascade", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: folder.id,
      content_ids: [ contents(:one).id, contents(:two).id ], user: @editor
    )
    remove_folder!(folder)
    dependents = @version.library_changes.where.not(id: root_change.id).ordered.to_a
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: @root.id, content_ids: [ contents(:one).id ], user: @editor
    )
    unrelated = @version.library_changes.last

    LibraryChanges::CascadeUndo.call(change: root_change, user: @editor, confirmed_dependent_ids: dependents.map(&:id))

    assert_predicate root_change.reload, :undone?
    dependents.each do |change|
      assert_predicate change.reload, :undone?
      assert_equal @editor, change.undone_by
    end
    refute LibraryFolder.exists?(folder.id)
    refute_predicate unrelated.reload, :undone?
    assert @root.library_folder_contents.exists?(content: contents(:one))
  end

  test "cascade requires a fresh confirmation of all dependent edits" do
    folder, root_change = create_recorded_folder!("Cascade", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: folder.id, content_ids: [ contents(:one).id ], user: @editor
    )

    error = assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::CascadeUndo.call(change: root_change, user: @editor, confirmed_dependent_ids: [])
    end
    assert_match(/Dependent edits have changed/, error.message)
    refute_predicate root_change.reload, :undone?
    assert folder.library_folder_contents.exists?(content: contents(:one))
  end

  test "only admins can cascade through another author's edits" do
    folder, root_change = create_recorded_folder!("Cascade", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: folder.id, content_ids: [ contents(:one).id ], user: @admin
    )
    dependent = @version.library_changes.last

    assert_raises(LibraryChanges::InvalidUndo) do
      LibraryChanges::CascadeUndo.call(change: root_change, user: @editor, confirmed_dependent_ids: [ dependent.id ])
    end
    refute_predicate dependent.reload, :undone?
    refute_predicate root_change.reload, :undone?

    LibraryChanges::CascadeUndo.call(change: root_change, user: @admin, confirmed_dependent_ids: [ dependent.id ])
    assert_predicate dependent.reload, :undone?
    assert_equal @admin, dependent.undone_by
    assert_predicate root_change.reload, :undone?
  end

  test "a failure reverses every mutation in a cascade" do
    folder, root_change = create_recorded_folder!("Cascade", parent_folder: @root)
    LibraryFolderOperations::PlaceContents.call(
      library: @library, folder_id: folder.id, content_ids: [ contents(:one).id ], user: @editor
    )
    dependent = @version.library_changes.last
    create_folder!("Unrecorded child", parent_folder: folder)

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      LibraryChanges::CascadeUndo.call(change: root_change, user: @editor, confirmed_dependent_ids: [ dependent.id ])
    end
    refute_predicate dependent.reload, :undone?
    refute_predicate root_change.reload, :undone?
    assert folder.library_folder_contents.exists?(content: contents(:one))
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

  def create_recorded_folder!(name, parent_folder:)
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

  def remove_folder!(folder)
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: folder.parent_folder_id,
      folder_ids: [ folder.id ],
      content_ids: [],
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
