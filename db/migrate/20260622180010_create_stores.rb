class CreateStores < ActiveRecord::Migration[8.1]
  def change
    create_table :stores do |t|
      t.references :user, null: false, foreign_key: true
      t.string :shopify_domain, null: false
      t.text :access_token, null: false

      t.timestamps
    end

    add_index :stores, :shopify_domain, unique: true
  end
end
