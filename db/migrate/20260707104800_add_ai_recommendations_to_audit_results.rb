class AddAiRecommendationsToAuditResults < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_results, :ai_recommendation, :text
    add_column :audit_results, :ai_provider, :string
    add_column :audit_results, :ai_model, :string
    add_column :audit_results, :ai_prompt_tokens, :integer, null: false, default: 0
    add_column :audit_results, :ai_completion_tokens, :integer, null: false, default: 0
    add_column :audit_results, :ai_total_tokens, :integer, null: false, default: 0
  end
end
