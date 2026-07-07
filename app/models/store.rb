class Store < ApplicationRecord
  SHOPIFY_DOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.myshopify\.com\z/

  belongs_to :user
  has_many :audit_runs, dependent: :destroy
  has_many :audit_results, through: :audit_runs
  has_many :order_line_item_snapshots, dependent: :destroy
  has_many :order_snapshots, dependent: :destroy
  has_many :product_snapshots, dependent: :destroy

  encrypts :access_token

  normalizes :shopify_domain, with: ->(domain) { domain.strip.downcase }

  validates :shopify_domain,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: SHOPIFY_DOMAIN_FORMAT }
  validates :access_token, presence: true, if: :active?
  validates :currency,
    length: { is: 3 },
    allow_blank: true
  validates :products_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :orders_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :orders_total_price,
    numericality: { greater_than_or_equal_to: 0 }
  validates :orders_currency,
    length: { is: 3 },
    allow_blank: true
  validates :owner_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true

  def mark_uninstalled!(at: Time.current)
    update!(active: false, access_token: nil, uninstalled_at: at)
  end
end
