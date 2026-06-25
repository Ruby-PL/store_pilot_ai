class CreateOrderSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :order_snapshots do |t|
      t.references :store, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.decimal :total_price, precision: 12, scale: 2, null: false, default: 0
      t.string :currency, null: false
      t.datetime :processed_at, null: false
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :order_snapshots, [ :store_id, :shopify_order_id ]
  end
end
