class Store < ApplicationRecord
  SHOPIFY_DOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.myshopify\.com\z/

  belongs_to :user

  encrypts :access_token

  normalizes :shopify_domain, with: ->(domain) { domain.strip.downcase }

  validates :shopify_domain,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: SHOPIFY_DOMAIN_FORMAT }
  validates :access_token, presence: true
  validates :currency,
    length: { is: 3 },
    allow_blank: true
  validates :owner_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true
end
