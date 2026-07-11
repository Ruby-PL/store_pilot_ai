class Store < ApplicationRecord
  AI_PLAN_LIMITS = {
    "free" => 50,
    "pro" => 250,
    "growth" => 500
  }.freeze

  SHOPIFY_DOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.myshopify\.com\z/

  belongs_to :user
  has_many :ai_conversations, dependent: :destroy
  has_many :audit_runs, dependent: :destroy
  has_many :audit_results, through: :audit_runs
  has_many :audit_actions, through: :audit_runs
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
  validates :ai_plan,
    inclusion: { in: AI_PLAN_LIMITS.keys },
    allow_blank: true
  validates :owner_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true

  def ai_plan
    super.presence || "free"
  end

  def ai_request_limit
    AI_PLAN_LIMITS.fetch(ai_plan, AI_PLAN_LIMITS["free"])
  end

  def ai_requests_count_current_month
    counted_in_current_month? ? ai_requests_count.to_i : 0
  end

  def ai_requests_remaining
    [ ai_request_limit - ai_requests_count_current_month, 0 ].max
  end

  def ai_usage_summary
    "#{ai_requests_count_current_month}/#{ai_request_limit}"
  end

  def ai_usage_limit_message
    "This store has reached its monthly AI limit on the #{ai_plan.titleize} plan. Upgrade to Pro or Growth to keep using AI this month."
  end

  def consume_ai_request!
    reset_ai_request_counter_if_needed!
    return false if ai_requests_count.to_i >= ai_request_limit

    update!(ai_requests_count: ai_requests_count.to_i + 1)
  end

  def counted_in_current_month?
    ai_requests_counted_on == current_ai_request_period
  end

  def current_ai_request_period
    Time.current.beginning_of_month.to_date
  end

  def reset_ai_request_counter_if_needed!
    return if counted_in_current_month?

    update!(ai_requests_count: 0, ai_requests_counted_on: current_ai_request_period)
  end

  def mark_uninstalled!(at: Time.current)
    update!(active: false, access_token: nil, uninstalled_at: at)
  end
end
