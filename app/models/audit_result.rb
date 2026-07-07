class AuditResult < ApplicationRecord
  STATUSES = %w[passed warning failed].freeze
  SEVERITIES = %w[low medium high].freeze
  PRIORITIES = %w[low medium high].freeze
  IMPACTS = %w[low medium high].freeze
  CATEGORIES = %w[revenue seo inventory product_quality operations].freeze

  belongs_to :audit_run

  validates :rule_key, :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }, allow_blank: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_blank: true
  validates :impact, inclusion: { in: IMPACTS }, allow_blank: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :opportunity_score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :prioritized, -> { order(opportunity_score: :desc, created_at: :asc) }
end
