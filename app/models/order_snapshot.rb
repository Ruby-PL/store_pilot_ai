class OrderSnapshot < ApplicationRecord
  belongs_to :store
  has_many :order_line_item_snapshots, dependent: :destroy

  validates :shopify_order_id, :currency, :processed_at, :captured_at, presence: true
  validates :currency, length: { is: 3 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0 }
end
