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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_104800) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_results", force: :cascade do |t|
    t.integer "ai_completion_tokens", default: 0, null: false
    t.string "ai_model"
    t.integer "ai_prompt_tokens", default: 0, null: false
    t.string "ai_provider"
    t.text "ai_recommendation"
    t.integer "ai_total_tokens", default: 0, null: false
    t.bigint "audit_run_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "details", default: {}, null: false
    t.text "error_message"
    t.string "impact"
    t.integer "opportunity_score", default: 0, null: false
    t.string "priority"
    t.text "recommendation"
    t.string "rule_key", null: false
    t.string "severity"
    t.string "status", default: "passed", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["audit_run_id", "rule_key"], name: "index_audit_results_on_audit_run_id_and_rule_key"
    t.index ["audit_run_id"], name: "index_audit_results_on_audit_run_id"
    t.index ["category"], name: "index_audit_results_on_category"
    t.index ["opportunity_score"], name: "index_audit_results_on_opportunity_score"
    t.index ["priority", "impact"], name: "index_audit_results_on_priority_and_impact"
    t.index ["status", "severity"], name: "index_audit_results_on_status_and_severity"
  end

  create_table "audit_runs", force: :cascade do |t|
    t.jsonb "category_scores", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "failed_rule_count", default: 0, null: false
    t.integer "overall_score"
    t.integer "previous_score_delta"
    t.integer "rule_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["overall_score"], name: "index_audit_runs_on_overall_score"
    t.index ["status"], name: "index_audit_runs_on_status"
    t.index ["store_id", "created_at"], name: "index_audit_runs_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_audit_runs_on_store_id"
  end

  create_table "order_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.datetime "processed_at", null: false
    t.string "shopify_order_id", null: false
    t.bigint "store_id", null: false
    t.decimal "total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "shopify_order_id"], name: "index_order_snapshots_on_store_id_and_shopify_order_id"
    t.index ["store_id"], name: "index_order_snapshots_on_store_id"
  end

  create_table "product_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "image_alt_text_count", default: 0, null: false
    t.integer "image_count", default: 0, null: false
    t.integer "inventory_quantity", default: 0, null: false
    t.decimal "price", precision: 12, scale: 2, default: "0.0", null: false
    t.text "seo_description"
    t.string "seo_title"
    t.string "shopify_product_id", null: false
    t.string "status"
    t.bigint "store_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "shopify_product_id"], name: "index_product_snapshots_on_store_id_and_shopify_product_id"
    t.index ["store_id"], name: "index_product_snapshots_on_store_id"
  end

  create_table "stores", force: :cascade do |t|
    t.text "access_token"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "name"
    t.integer "orders_count", default: 0, null: false
    t.string "orders_currency"
    t.datetime "orders_synced_at"
    t.decimal "orders_total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.string "owner_email"
    t.integer "products_count", default: 0, null: false
    t.datetime "products_synced_at"
    t.string "shopify_domain", null: false
    t.string "shopify_plan"
    t.datetime "uninstalled_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shopify_domain"], name: "index_stores_on_shopify_domain", unique: true
    t.index ["user_id"], name: "index_stores_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
  end

  add_foreign_key "audit_results", "audit_runs"
  add_foreign_key "audit_runs", "stores"
  add_foreign_key "order_snapshots", "stores"
  add_foreign_key "product_snapshots", "stores"
  add_foreign_key "stores", "users"
end
