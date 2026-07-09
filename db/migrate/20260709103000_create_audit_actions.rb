class CreateAuditActions < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_actions do |t|
      t.references :audit_run, null: false, foreign_key: true
      t.references :audit_result, null: false, foreign_key: true, index: { unique: true }
      t.string :title, null: false
      t.text :next_step, null: false
      t.text :rationale
      t.string :status, null: false, default: "open"
      t.datetime :completed_at

      t.timestamps
    end

    add_index :audit_actions, [ :audit_run_id, :status ]
  end
end
