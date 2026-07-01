class CreateAuditResults < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_results do |t|
      t.references :audit_run, null: false, foreign_key: true
      t.string :rule_key, null: false
      t.string :status, null: false, default: "passed"
      t.string :severity
      t.string :category
      t.string :title, null: false
      t.text :description
      t.text :recommendation
      t.jsonb :details, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :audit_results, [ :audit_run_id, :rule_key ]
    add_index :audit_results, [ :status, :severity ]
    add_index :audit_results, :category
  end
end
