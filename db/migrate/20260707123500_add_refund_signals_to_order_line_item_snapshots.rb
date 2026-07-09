class AddRefundSignalsToOrderLineItemSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :order_line_item_snapshots, :refunded_quantity, :integer, null: false, default: 0
    add_column :order_line_item_snapshots, :refunded_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
  end
end
