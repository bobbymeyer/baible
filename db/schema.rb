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

ActiveRecord::Schema[8.1].define(version: 2026_10_06_191300) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "batches", force: :cascade do |t|
    t.integer "subject_id", null: false
    t.integer "variant_id"
    t.json "recipe", default: {}, null: false
    t.string "status", default: "queued", null: false
    t.text "error"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id"], name: "index_batches_on_subject_id"
    t.index ["variant_id"], name: "index_batches_on_variant_id"
  end

  create_table "candidates", force: :cascade do |t|
    t.integer "batch_id", null: false
    t.integer "position", null: false
    t.integer "seed", null: false
    t.string "comfy_prompt_id"
    t.string "status", default: "queued", null: false
    t.text "error"
    t.boolean "transparent"
    t.float "run_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_candidates_on_batch_id"
  end

  create_table "kinds", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "name", null: false
    t.string "medium", default: "image", null: false
    t.text "prompt"
    t.text "negative"
    t.string "model"
    t.json "loras", default: [], null: false
    t.integer "width", default: 1024, null: false
    t.integer "height", default: 1024, null: false
    t.boolean "transparent", default: false, null: false
    t.integer "seconds", default: 60, null: false
    t.json "variant_presets", default: [], null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_kinds_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_kinds_on_project_id"
  end

  create_table "picks", force: :cascade do |t|
    t.integer "subject_id", null: false
    t.integer "variant_id"
    t.integer "seed"
    t.text "prompt"
    t.json "recipe", default: {}, null: false
    t.float "run_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id", "variant_id"], name: "index_picks_on_subject_id_and_variant_id", unique: true
    t.index ["subject_id"], name: "index_picks_on_subject_id"
    t.index ["variant_id"], name: "index_picks_on_variant_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "style"
    t.text "negative"
    t.string "model"
    t.json "loras", default: [], null: false
    t.text "sound"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "comfy_url"
    t.string "comfy_model"
    t.string "music_model"
    t.string "rmbg_model"
    t.string "llm_url"
    t.string "llm_model"
    t.integer "draft_size"
    t.integer "draft_steps"
    t.float "draft_denoise"
    t.integer "candidates"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subjects", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "kind_id", null: false
    t.string "name", null: false
    t.text "notes"
    t.string "model"
    t.json "loras", default: [], null: false
    t.text "lyrics"
    t.integer "seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind_id", "name"], name: "index_subjects_on_kind_id_and_name", unique: true
    t.index ["kind_id"], name: "index_subjects_on_kind_id"
    t.index ["project_id"], name: "index_subjects_on_project_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "variants", force: :cascade do |t|
    t.integer "subject_id", null: false
    t.string "name", null: false
    t.text "prompt"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id", "name"], name: "index_variants_on_subject_id_and_name", unique: true
    t.index ["subject_id"], name: "index_variants_on_subject_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "batches", "subjects"
  add_foreign_key "batches", "variants"
  add_foreign_key "candidates", "batches"
  add_foreign_key "kinds", "projects"
  add_foreign_key "picks", "subjects"
  add_foreign_key "picks", "variants"
  add_foreign_key "sessions", "users"
  add_foreign_key "subjects", "kinds"
  add_foreign_key "subjects", "projects"
  add_foreign_key "variants", "subjects"
end
