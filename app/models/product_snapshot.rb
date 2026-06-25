class ProductSnapshot < ApplicationRecord
  belongs_to :store

  validates :shopify_product_id, :title, :captured_at, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :inventory_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
