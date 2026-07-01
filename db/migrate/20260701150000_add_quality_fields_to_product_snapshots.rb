class AddQualityFieldsToProductSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :product_snapshots, :description, :text
    add_column :product_snapshots, :image_count, :integer, null: false, default: 0
  end
end
