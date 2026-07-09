class AddWinBackEmailDraftToAuditResults < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_results, :win_back_email_draft, :text
  end
end
