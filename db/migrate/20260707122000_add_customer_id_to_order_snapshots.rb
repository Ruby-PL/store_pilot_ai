class AddCustomerIdToOrderSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :order_snapshots, :shopify_customer_id, :string
    add_index :order_snapshots, [ :store_id, :shopify_customer_id ], name: "index_order_snapshots_on_store_and_customer"
  end
end
