class AddOrderSyncFieldsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :orders_count, :integer, null: false, default: 0
    add_column :stores, :orders_total_price, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :stores, :orders_currency, :string
    add_column :stores, :orders_synced_at, :datetime
  end
end
