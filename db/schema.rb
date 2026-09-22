# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_22_122000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_shelves", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "shelf_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shelf_id"], name: "index_active_shelves_on_shelf_id"
    t.index ["user_id", "position"], name: "index_active_shelves_on_user_id_and_position", unique: true
    t.index ["user_id", "shelf_id"], name: "index_active_shelves_on_user_id_and_shelf_id", unique: true
    t.index ["user_id"], name: "index_active_shelves_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "content_table_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "state", default: {}, null: false
    t.string "table_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "table_key"], name: "index_content_table_preferences_on_user_id_and_table_key", unique: true
    t.index ["user_id"], name: "index_content_table_preferences_on_user_id"
  end

  create_table "contents", force: :cascade do |t|
    t.integer "additional_notes"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_title"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year_of_publication"
    t.index ["user_id"], name: "index_contents_on_user_id"
  end

  create_table "contents_metadata", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.bigint "metadata_id", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_contents_metadata_on_content_id"
    t.index ["metadata_id"], name: "index_contents_metadata_on_metadata_id"
  end

  create_table "libraries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_version_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["current_version_id"], name: "index_libraries_on_current_version_id", unique: true
    t.index ["name"], name: "index_libraries_on_name"
    t.index ["user_id"], name: "index_libraries_on_user_id"
  end

  create_table "library_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "language"
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_library_assets_on_user_id"
  end

  create_table "library_change_dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_change_id", null: false
    t.bigint "prerequisite_change_id", null: false
    t.datetime "updated_at", null: false
    t.index ["library_change_id", "prerequisite_change_id"], name: "index_library_change_dependencies_unique", unique: true
    t.index ["library_change_id"], name: "index_library_change_dependencies_on_library_change_id"
    t.index ["prerequisite_change_id"], name: "index_library_change_dependencies_on_prerequisite_change_id"
    t.check_constraint "prerequisite_change_id < library_change_id", name: "library_change_dependencies_chronological"
  end

  create_table "library_change_targets", force: :cascade do |t|
    t.bigint "content_id"
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.boolean "direct", default: true, null: false
    t.string "effect", null: false
    t.bigint "folder_id", null: false
    t.string "label", null: false
    t.bigint "library_change_id", null: false
    t.string "resource_key", null: false
    t.bigint "target_id", null: false
    t.string "target_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id"], name: "index_library_change_targets_on_folder_id"
    t.index ["library_change_id", "resource_key"], name: "index_library_change_targets_unique_resource", unique: true
    t.index ["library_change_id"], name: "index_library_change_targets_on_library_change_id"
    t.index ["resource_key"], name: "index_library_change_targets_on_resource_key"
    t.index ["target_kind", "target_id"], name: "index_library_change_targets_on_kind_and_target"
    t.check_constraint "effect::text = ANY (ARRAY['new'::character varying, 'moved'::character varying, 'removed'::character varying]::text[])", name: "library_change_targets_effect"
    t.check_constraint "target_kind::text = 'folder'::text AND content_id IS NULL OR target_kind::text = 'content'::text AND content_id IS NOT NULL", name: "library_change_targets_identifier_shape"
    t.check_constraint "target_kind::text = ANY (ARRAY['folder'::character varying, 'content'::character varying]::text[])", name: "library_change_targets_kind"
  end

  create_table "library_changes", force: :cascade do |t|
    t.string "action_type", null: false
    t.string "batch_key", null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.bigint "library_version_id", null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["batch_key"], name: "index_library_changes_on_batch_key"
    t.index ["library_version_id", "status", "id"], name: "index_library_changes_on_version_status_id"
    t.index ["library_version_id"], name: "index_library_changes_on_library_version_id"
    t.index ["resolved_by_id"], name: "index_library_changes_on_resolved_by_id"
    t.index ["user_id"], name: "index_library_changes_on_user_id"
    t.check_constraint "action_type::text = ANY (ARRAY['add_folder'::character varying, 'add_content'::character varying, 'move_folder'::character varying, 'move_content'::character varying, 'remove_folder'::character varying, 'remove_content'::character varying, 'duplicate_folder'::character varying, 'duplicate_content'::character varying]::text[])", name: "library_changes_action_type"
    t.check_constraint "status::text = 'pending'::text AND resolved_at IS NULL AND resolved_by_id IS NULL OR status::text <> 'pending'::text AND resolved_at IS NOT NULL AND resolved_by_id IS NOT NULL", name: "library_changes_resolution"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'undone'::character varying]::text[])", name: "library_changes_status"
  end

  create_table "library_folder_contents", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.bigint "library_folder_id", null: false
    t.bigint "library_version_id", null: false
    t.bigint "pending_removal_change_id"
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_library_folder_contents_on_content_id"
    t.index ["library_folder_id", "content_id"], name: "idx_on_library_folder_id_content_id_f0777ce9d7", unique: true
    t.index ["library_folder_id"], name: "index_library_folder_contents_on_library_folder_id"
    t.index ["library_version_id"], name: "index_library_folder_contents_on_library_version_id"
    t.index ["pending_removal_change_id"], name: "index_library_folder_contents_on_pending_removal_change_id"
  end

  create_table "library_folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.bigint "library_version_id", null: false
    t.bigint "logo_id"
    t.string "name", null: false
    t.bigint "parent_folder_id"
    t.bigint "pending_removal_change_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["id", "library_version_id"], name: "index_library_folders_on_id_and_library_version_id", unique: true
    t.index ["library_id"], name: "index_library_folders_on_library_id"
    t.index ["library_version_id"], name: "index_library_folders_on_library_version_id"
    t.index ["logo_id"], name: "index_library_folders_on_logo_id"
    t.index ["parent_folder_id"], name: "index_library_folders_on_parent_folder_id"
    t.index ["pending_removal_change_id"], name: "index_library_folders_on_pending_removal_change_id"
    t.index ["user_id"], name: "index_library_folders_on_user_id"
    t.check_constraint "parent_folder_id IS NULL AND logo_id IS NOT NULL OR parent_folder_id IS NOT NULL AND logo_id IS NULL", name: "library_folders_root_only_logo"
  end

  create_table "library_version_contents", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.string "file_checksum"
    t.bigint "library_version_id", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_library_version_contents_on_content_id"
    t.index ["library_version_id", "content_id"], name: "index_library_version_contents_on_version_and_content", unique: true
    t.index ["library_version_id"], name: "index_library_version_contents_on_library_version_id"
  end

  create_table "library_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.datetime "locked_at"
    t.bigint "previous_version_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "version_number", null: false
    t.index ["id", "library_id"], name: "index_library_versions_on_id_and_library_id", unique: true
    t.index ["library_id", "version_number"], name: "index_library_versions_on_library_id_and_version_number", unique: true
    t.index ["library_id"], name: "index_library_versions_on_library_id"
    t.index ["library_id"], name: "index_library_versions_on_one_unlocked_per_library", unique: true, where: "(locked_at IS NULL)"
    t.index ["previous_version_id"], name: "index_library_versions_on_previous_version_id", unique: true
    t.index ["user_id"], name: "index_library_versions_on_user_id"
  end

  create_table "metadata", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "metadata_type_id", null: false
    t.string "name", null: false
    t.boolean "under_review", default: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["metadata_type_id"], name: "index_metadata_on_metadata_type_id"
    t.index ["user_id"], name: "index_metadata_on_user_id"
  end

  create_table "metadata_types", force: :cascade do |t|
    t.integer "access_level", default: 1
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "order", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_metadata_types_on_user_id"
  end

  create_table "shelf_contents", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.bigint "shelf_id", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_shelf_contents_on_content_id"
    t.index ["shelf_id", "content_id"], name: "index_shelf_contents_on_shelf_id_and_content_id", unique: true
    t.index ["shelf_id"], name: "index_shelf_contents_on_shelf_id"
  end

  create_table "shelves", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_shelves_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_shelves", "shelves"
  add_foreign_key "active_shelves", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "content_table_preferences", "users"
  add_foreign_key "contents", "users"
  add_foreign_key "contents_metadata", "contents"
  add_foreign_key "contents_metadata", "metadata", column: "metadata_id"
  add_foreign_key "libraries", "library_versions", column: "current_version_id"
  add_foreign_key "libraries", "library_versions", column: ["current_version_id", "id"], primary_key: ["id", "library_id"], name: "fk_libraries_current_version_library"
  add_foreign_key "libraries", "users"
  add_foreign_key "library_assets", "users"
  add_foreign_key "library_change_dependencies", "library_changes"
  add_foreign_key "library_change_dependencies", "library_changes", column: "prerequisite_change_id"
  add_foreign_key "library_change_targets", "library_changes"
  add_foreign_key "library_changes", "library_versions"
  add_foreign_key "library_changes", "users"
  add_foreign_key "library_changes", "users", column: "resolved_by_id"
  add_foreign_key "library_folder_contents", "contents"
  add_foreign_key "library_folder_contents", "library_changes", column: "pending_removal_change_id"
  add_foreign_key "library_folder_contents", "library_folders"
  add_foreign_key "library_folder_contents", "library_folders", column: ["library_folder_id", "library_version_id"], primary_key: ["id", "library_version_id"], name: "fk_folder_contents_folder_version"
  add_foreign_key "library_folder_contents", "library_version_contents", column: ["library_version_id", "content_id"], primary_key: ["library_version_id", "content_id"], name: "fk_folder_contents_manifest"
  add_foreign_key "library_folder_contents", "library_versions"
  add_foreign_key "library_folders", "libraries"
  add_foreign_key "library_folders", "library_assets", column: "logo_id"
  add_foreign_key "library_folders", "library_changes", column: "pending_removal_change_id"
  add_foreign_key "library_folders", "library_folders", column: "parent_folder_id"
  add_foreign_key "library_folders", "library_folders", column: ["parent_folder_id", "library_version_id"], primary_key: ["id", "library_version_id"], name: "fk_library_folders_parent_version"
  add_foreign_key "library_folders", "library_versions"
  add_foreign_key "library_folders", "library_versions", column: ["library_version_id", "library_id"], primary_key: ["id", "library_id"], name: "fk_library_folders_version_library"
  add_foreign_key "library_folders", "users"
  add_foreign_key "library_version_contents", "contents"
  add_foreign_key "library_version_contents", "library_versions"
  add_foreign_key "library_versions", "libraries"
  add_foreign_key "library_versions", "library_versions", column: "previous_version_id"
  add_foreign_key "library_versions", "users"
  add_foreign_key "metadata", "metadata_types"
  add_foreign_key "metadata", "users"
  add_foreign_key "metadata_types", "users"
  add_foreign_key "shelf_contents", "contents"
  add_foreign_key "shelf_contents", "shelves"
  add_foreign_key "shelves", "users"
end
