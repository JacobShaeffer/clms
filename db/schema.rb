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

ActiveRecord::Schema[8.1].define(version: 2026_08_13_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "library_folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.bigint "logo_id", null: false
    t.string "name", null: false
    t.bigint "parent_folder_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["library_id"], name: "index_library_folders_on_library_id"
    t.index ["logo_id"], name: "index_library_folders_on_logo_id"
    t.index ["parent_folder_id"], name: "index_library_folders_on_parent_folder_id"
    t.index ["user_id"], name: "index_library_folders_on_user_id"
  end

  create_table "library_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.bigint "previous_version_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "version_number", null: false
    t.index ["library_id", "version_number"], name: "index_library_versions_on_library_id_and_version_number", unique: true
    t.index ["library_id"], name: "index_library_versions_on_library_id"
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
    t.integer "access_level", default: 0
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "contents", "users"
  add_foreign_key "contents_metadata", "contents"
  add_foreign_key "contents_metadata", "metadata", column: "metadata_id"
  add_foreign_key "libraries", "library_versions", column: "current_version_id"
  add_foreign_key "libraries", "users"
  add_foreign_key "library_assets", "users"
  add_foreign_key "library_folders", "libraries"
  add_foreign_key "library_folders", "library_assets", column: "logo_id"
  add_foreign_key "library_folders", "library_folders", column: "parent_folder_id"
  add_foreign_key "library_folders", "users"
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
