class AddAiUsageTrackingToStores < ActiveRecord::Migration[8.0]
  def change
    add_column :stores, :ai_plan, :string, null: false, default: "free"
    add_column :stores, :ai_requests_count, :integer, null: false, default: 0
    add_column :stores, :ai_requests_counted_on, :date
  end
end
