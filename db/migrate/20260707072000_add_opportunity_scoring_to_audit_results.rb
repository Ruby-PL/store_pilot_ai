class AddOpportunityScoringToAuditResults < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_results, :priority, :string
    add_column :audit_results, :impact, :string
    add_column :audit_results, :opportunity_score, :integer, null: false, default: 0

    add_index :audit_results, [ :priority, :impact ]
    add_index :audit_results, :opportunity_score
  end
end
