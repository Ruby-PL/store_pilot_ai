class CreateProductSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :product_snapshots do |t|
      t.references :store, null: false, foreign_key: true
      t.string :shopify_product_id, null: false
      t.string :title, null: false
      t.decimal :price, precision: 12, scale: 2, null: false, default: 0
      t.integer :inventory_quantity, null: false, default: 0
      t.string :status
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :product_snapshots, [ :store_id, :shopify_product_id ]
  end
end
