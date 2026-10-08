require "test_helper"

class LibraryChanges::HistoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @library = Library.create!(name: "History Library", user: @user)
    @version = @library.current_version
  end

  test "shows shared dependents once and finds all transitive dependents" do
    root = create_change
    first = create_change(root)
    second = create_change(root)
    shared = create_change(first, second)
    unrelated = create_change
    history = load_history

    assert_equal [ first.id, second.id, shared.id ], history.dependent_changes(root).map(&:id)
    assert_equal [ first.id, second.id ], history.prerequisites(shared).map(&:id)
    assert_equal [ [ root.id, 0 ], [ first.id, 1 ], [ second.id, 1 ], [ shared.id, 2 ], [ unrelated.id, 0 ] ],
      history.rows.map { |change, depth| [ change.id, depth ] }
  end

  test "retains undone edits in history while excluding them from undo previews" do
    root = create_change
    child = create_change(root)
    child.update!(undone_at: Time.current, undone_by: @user)
    history = load_history

    assert_equal [ child.id ], history.dependent_changes(root).map(&:id)
    assert_empty history.dependent_changes(root, active_only: true)
    assert_equal 2, history.rows.length
  end

  test "hides content rows while retaining dependencies and promoting visible descendants" do
    root = create_change
    content = contents(:one)
    hidden = LibraryChanges::Recorder.call(
      library_version: @version, user: @user, action_type: :add_content,
      details: { content_id: content.id }, dependency_change_ids: [ root.id ],
      targets: [ {
        target_kind: :content, target_id: 1, folder_id: 1, content_id: content.id,
        resource_key: "content:1:#{content.id}", effect: :new, direct: true, label: content.title
      } ]
    )
    descendant = create_change(hidden)
    history = load_history(hidden_content_ids: [ content.id ])

    assert_equal [ root.id, descendant.id ], history.visible_changes.map(&:id)
    assert_equal [ [ root.id, 0 ], [ descendant.id, 1 ] ], history.rows.map { |change, depth| [ change.id, depth ] }
    assert_equal [ hidden.id, descendant.id ], history.dependent_changes(root).map(&:id)
    assert_empty history.visible_targets(hidden)
    assert_equal 3, @version.library_changes.count
  end

  private

  def load_history(hidden_content_ids: [])
    LibraryChanges::History.new(
      changes: @version.library_changes.includes(:dependency_links, :library_change_targets).ordered,
      hidden_content_ids:
    )
  end

  def create_change(*prerequisites)
    LibraryChanges::Recorder.call(
      library_version: @version, user: @user, action_type: :add_folder,
      details: { folder_id: 1 }, targets: [], dependency_change_ids: prerequisites.map(&:id)
    )
  end
end
