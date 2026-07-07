class AddStoreHealthScoringToAuditRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_runs, :overall_score, :integer
    add_column :audit_runs, :category_scores, :jsonb, null: false, default: {}
    add_column :audit_runs, :previous_score_delta, :integer

    add_index :audit_runs, :overall_score
  end
end
