class CreateOrderLineItemSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :order_line_item_snapshots do |t|
      t.references :order_snapshot, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.string :shopify_line_item_id, null: false
      t.string :shopify_product_id, null: false
      t.string :product_title, null: false
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :order_line_item_snapshots,
      [ :store_id, :shopify_product_id ],
      name: "index_order_line_items_on_store_and_product"
    add_index :order_line_item_snapshots,
      [ :order_snapshot_id, :shopify_line_item_id ],
      name: "index_order_line_items_on_order_and_line_item"
  end
end
