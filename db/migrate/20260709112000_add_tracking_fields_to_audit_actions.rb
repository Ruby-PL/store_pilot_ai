class AddTrackingFieldsToAuditActions < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_actions, :merchant_note, :text
    add_column :audit_actions, :reference_url, :text
  end
end
