class CreateLibraryChanges < ActiveRecord::Migration[8.1]
  ACTION_TYPES = %w[
    add_folder add_content move_folder move_content
    remove_folder remove_content duplicate_folder duplicate_content
  ].freeze
  STATUSES = %w[pending approved undone].freeze
  TARGET_KINDS = %w[folder content].freeze
  EFFECTS = %w[new moved removed].freeze

  def change
    create_table :library_changes do |t|
      t.references :library_version, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.string :action_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :batch_key, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :resolved_at

      t.timestamps
    end
    add_index :library_changes, [ :library_version_id, :status, :id ],
      name: "index_library_changes_on_version_status_id"
    add_index :library_changes, :batch_key
    add_check_constraint :library_changes,
      "action_type IN (#{ACTION_TYPES.map { |value| connection.quote(value) }.join(', ')})",
      name: "library_changes_action_type"
    add_check_constraint :library_changes,
      "status IN (#{STATUSES.map { |value| connection.quote(value) }.join(', ')})",
      name: "library_changes_status"
    add_check_constraint :library_changes,
      "(status = 'pending' AND resolved_at IS NULL AND resolved_by_id IS NULL) OR " \
        "(status <> 'pending' AND resolved_at IS NOT NULL AND resolved_by_id IS NOT NULL)",
      name: "library_changes_resolution"

    create_table :library_change_dependencies do |t|
      t.references :library_change, null: false, foreign_key: true
      t.references :prerequisite_change,
        null: false,
        foreign_key: { to_table: :library_changes }

      t.timestamps
    end
    add_index :library_change_dependencies,
      [ :library_change_id, :prerequisite_change_id ],
      unique: true,
      name: "index_library_change_dependencies_unique"
    add_check_constraint :library_change_dependencies,
      "library_change_id <> prerequisite_change_id",
      name: "library_change_dependencies_not_self"

    create_table :library_change_targets do |t|
      t.references :library_change, null: false, foreign_key: true
      t.string :target_kind, null: false
      t.bigint :target_id
      t.bigint :folder_id
      t.bigint :content_id
      t.string :resource_key, null: false
      t.string :effect, null: false
      t.boolean :direct, null: false, default: true
      t.string :label, null: false
      t.jsonb :details, null: false, default: {}

      t.timestamps
    end
    add_index :library_change_targets, [ :target_kind, :target_id ],
      name: "index_library_change_targets_on_kind_and_target"
    add_index :library_change_targets, :resource_key
    add_index :library_change_targets, [ :library_change_id, :resource_key ],
      unique: true,
      name: "index_library_change_targets_unique_resource"
    add_check_constraint :library_change_targets,
      "target_kind IN (#{TARGET_KINDS.map { |value| connection.quote(value) }.join(', ')})",
      name: "library_change_targets_kind"
    add_check_constraint :library_change_targets,
      "effect IN (#{EFFECTS.map { |value| connection.quote(value) }.join(', ')})",
      name: "library_change_targets_effect"

    add_reference :library_folders,
      :pending_removal_change,
      foreign_key: { to_table: :library_changes },
      index: true
    add_reference :library_folder_contents,
      :pending_removal_change,
      foreign_key: { to_table: :library_changes },
      index: true
  end
end
