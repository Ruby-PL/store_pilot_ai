class AddSeoFieldsToProductSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :product_snapshots, :seo_title, :string
    add_column :product_snapshots, :seo_description, :text
    add_column :product_snapshots, :image_alt_text_count, :integer, null: false, default: 0
  end
end
