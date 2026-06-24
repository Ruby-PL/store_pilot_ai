class AddProductSyncFieldsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :products_count, :integer, null: false, default: 0
    add_column :stores, :products_synced_at, :datetime
  end
end
