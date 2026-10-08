require "test_helper"

class LibraryChangeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @library = Library.create!(name: "Change Model Library", user: @user)
    @version = @library.current_version
  end

  test "applied and undone changes are immutable" do
    change = create_change!

    assert_not change.update(details: { changed: true })
    assert_includes change.errors[:base], "Library change audit records can only be marked undone"

    change.reload
    change.update!(undone_by: @user, undone_at: Time.current)

    assert_predicate change, :undone?
    assert_not change.update(undone_at: 1.minute.from_now)
    assert_includes change.errors[:base], "Undone library changes cannot be modified"
  end

  test "dependencies must be older and in the same version" do
    prerequisite = create_change!
    dependent = create_change!
    assert dependent.dependency_links.create!(prerequisite_change: prerequisite)

    reverse = prerequisite.dependency_links.build(prerequisite_change: dependent)
    assert_not reverse.valid?
    assert_includes reverse.errors[:prerequisite_change], "must be older than the dependent change"

    other_library = Library.create!(name: "Other Change Library", user: @user)
    other_change = other_library.current_version.library_changes.create!(
      user: @user,
      action_type: :add_folder,
      batch_key: SecureRandom.uuid,
      details: { folder_id: 2 }
    )
    cross_version = dependent.dependency_links.build(prerequisite_change: other_change)
    assert_not cross_version.valid?
    assert_includes cross_version.errors[:prerequisite_change], "must belong to the same library version"

    duplicate = dependent.dependency_links.build(prerequisite_change: prerequisite)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:prerequisite_change_id], "has already been taken"
  end

  test "replay data stays immutable until the validated redo transition" do
    change = create_change!
    assert_not change.update(replay_snapshot: { applied: {}, undone: {} }, undo_group_key: "group")
    change.reload.update!(undone_by: @user, undone_at: Time.current,
      replay_snapshot: { applied: {}, undone: {} }, undo_group_key: "group")
    assert_not change.update(replay_snapshot: { changed: true })
    assert_not change.reload.update(undo_group_key: "another-group")
    assert_not change.reload.update(undone_by: nil, undone_at: nil)
    assert_not change.reload.update(undone_by: nil, undone_at: nil, replay_snapshot: nil,
      undo_group_key: nil, replay_generation: 1)
    change.reload.mark_redone!
    refute_predicate change, :undone?
    assert_nil change.replay_snapshot
    assert_nil change.undo_group_key
    assert_nil change.undone_by_id
    assert_equal 1, change.replay_generation
    assert_not change.update(details: { changed: true })
    assert_not change.reload.update(replay_generation: 2)
  end

  test "redo state cannot be cleared without saved data or in a locked version" do
    change = create_change!
    assert_raises(ActiveRecord::RecordInvalid) { change.mark_redone! }
    change.reload.update!(undone_by: @user, undone_at: Time.current)
    assert_raises(ActiveRecord::RecordInvalid) { change.mark_redone! }
    change.reload.update_columns(replay_snapshot: { applied: {}, undone: {} }, undo_group_key: "group")
    @version.update_column(:locked_at, Time.current)
    assert_raises(ActiveRecord::RecordInvalid) { change.reload.mark_redone! }
    assert_predicate change.reload, :undone?
    assert_equal 0, change.replay_generation
  end

  test "database rejects non-chronological dependency edges" do
    older = create_change!
    newer = create_change!

    assert_raises(ActiveRecord::StatementInvalid) do
      LibraryChangeDependency.insert_all!([ {
        library_change_id: older.id,
        prerequisite_change_id: newer.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "locked versions reject new changes" do
    @version.update_column(:locked_at, Time.current)

    change = @version.library_changes.build(
      user: @user,
      action_type: :add_folder,
      batch_key: SecureRandom.uuid,
      details: { folder_id: 1 }
    )
    assert_not change.valid?
    assert_includes change.errors[:base], "Locked library version changes cannot be modified"
  end

  test "database requires undo time and user together" do
    change = create_change!

    assert_raises(ActiveRecord::StatementInvalid) do
      change.update_columns(undone_at: Time.current)
    end
  end

  test "changes targets and dependencies are retained as immutable audit records" do
    prerequisite = create_change!
    change = create_change!
    dependency = change.dependency_links.create!(prerequisite_change: prerequisite)
    target = change.library_change_targets.create!(
      target_kind: :folder,
      target_id: 123,
      folder_id: 123,
      resource_key: "folder:123",
      effect: :new,
      direct: true,
      label: "Snapshot",
      details: { path: "/Snapshot" }
    )

    assert_not change.destroy
    assert_includes change.errors[:base], "Library change audit records cannot be deleted"
    assert_not target.update(label: "Changed")
    assert_not target.destroy
    assert_not dependency.update(created_at: 1.day.ago)
    assert_not dependency.destroy
  end

  test "recorder stores a path snapshot on every target" do
    root = @version.library_folders.create!(
      library: @library,
      name: "Root",
      user: @user,
      logo: library_assets(:one)
    )
    child = @version.library_folders.create!(
      library: @library,
      name: "Child",
      parent_folder: root,
      user: @user
    )

    change = LibraryChanges::Recorder.call(
      library_version: @version,
      user: @user,
      action_type: :add_folder,
      details: { folder_id: child.id },
      targets: [ {
        target_kind: :folder,
        target_id: child.id,
        folder_id: child.id,
        resource_key: LibraryChanges::Recorder.folder_key(child),
        effect: :new,
        direct: true,
        label: child.name
      } ]
    )

    assert_equal "/Root/Child", change.library_change_targets.first.details.fetch("path")
  end

  test "recorder rolls back the change when a target is invalid" do
    assert_no_difference([ "LibraryChange.count", "LibraryChangeTarget.count" ]) do
      assert_raises(ActiveRecord::RecordInvalid) do
        LibraryChanges::Recorder.call(
          library_version: @version,
          user: @user,
          action_type: :add_folder,
          details: { folder_id: 1 },
          targets: [ {
            target_kind: :folder,
            target_id: nil,
            folder_id: 1,
            resource_key: "folder:1",
            effect: :new,
            direct: true,
            label: "Invalid"
          } ]
        )
      end
    end
  end

  private

  def create_change!
    @version.library_changes.create!(
      user: @user,
      action_type: :add_folder,
      batch_key: SecureRandom.uuid,
      details: { folder_id: 1 }
    )
  end
end
