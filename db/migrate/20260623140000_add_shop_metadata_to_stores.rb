class AddShopMetadataToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :name, :string
    add_column :stores, :owner_email, :string
    add_column :stores, :currency, :string
    add_column :stores, :shopify_plan, :string
  end
end
