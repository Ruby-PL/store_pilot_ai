class CreateAuditRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_runs do |t|
      t.references :store, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :rule_count, null: false, default: 0
      t.integer :failed_rule_count, null: false, default: 0

      t.timestamps
    end

    add_index :audit_runs, [ :store_id, :created_at ]
    add_index :audit_runs, :status
  end
end
