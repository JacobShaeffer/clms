require "test_helper"
require Rails.root.join("db/migrate/20261009002000_remove_unused_redo_links")

class LibraryChanges::RedoMigrationTest < ActiveSupport::TestCase
  test "retains old redo history while removing superseded replay data" do
    with_legacy_redo_column do |migration|
      original, replacement = legacy_redo_pair
      original_attributes = original.attributes.except("replay_snapshot", "undo_group_key", "redo_of_id")
      replacement_attributes = replacement.attributes.except("redo_of_id")

      assert_no_difference("LibraryChange.count") do
        ActiveRecord::Migration.suppress_messages { migration.up }
      end
      LibraryChange.reset_column_information

      refute ActiveRecord::Base.connection.column_exists?(:library_changes, :redo_of_id)
      assert_equal original_attributes, original.reload.attributes.except("replay_snapshot", "undo_group_key")
      assert_nil original.replay_snapshot
      assert_nil original.undo_group_key
      assert_equal replacement_attributes, replacement.reload.attributes
    end
  end

  test "refuses to remove redo links when dependency history needs conversion" do
    with_legacy_redo_column do |migration|
      original, replacement = legacy_redo_pair
      dependent = original.library_version.library_changes.create!(user: original.user, action_type: :add_content,
        batch_key: SecureRandom.uuid, details: { content_id: 2 })
      dependent.dependency_links.create!(prerequisite_change: original)

      assert_raises(ActiveRecord::MigrationError) do
        ActiveRecord::Migration.suppress_messages { migration.up }
      end

      assert ActiveRecord::Base.connection.column_exists?(:library_changes, :redo_of_id)
      assert_predicate original.reload.replay_snapshot, :present?
      assert_equal original.id, ActiveRecord::Base.connection.select_value("SELECT redo_of_id FROM library_changes WHERE id = #{replacement.id}")
    end
  end

  private

  def with_legacy_redo_column
    ActiveRecord::Base.transaction(requires_new: true) do
      migration = RemoveUnusedRedoLinks.new
      ActiveRecord::Migration.suppress_messages { migration.down }
      yield migration
      raise ActiveRecord::Rollback
    end
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
    LibraryChange.reset_column_information
  end

  def legacy_redo_pair
    user = users(:one)
    library = Library.create!(name: "Legacy Redo Library", user:)
    original = library.current_version.library_changes.create!(user:, action_type: :add_content,
      batch_key: SecureRandom.uuid, details: { content_id: 1 })
    original.update!(undone_at: Time.current, undone_by: user,
      replay_snapshot: { applied: {}, undone: {} }, undo_group_key: SecureRandom.uuid)
    replacement = library.current_version.library_changes.create!(user:, action_type: :add_content,
      batch_key: SecureRandom.uuid, details: { content_id: 1 })
    ActiveRecord::Base.connection.execute("UPDATE library_changes SET redo_of_id = #{original.id} WHERE id = #{replacement.id}")
    [ original, replacement ]
  end
end
