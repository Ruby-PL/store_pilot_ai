class OrderLineItemSnapshot < ApplicationRecord
  belongs_to :order_snapshot
  belongs_to :store

  validates :shopify_line_item_id, :shopify_product_id, :product_title, :captured_at, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
end
