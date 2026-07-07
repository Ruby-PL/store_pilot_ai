class AuditRun < ApplicationRecord
  STATUSES = %w[running completed completed_with_failures failed].freeze

  belongs_to :store
  has_many :audit_results, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validates :rule_count, :failed_rule_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :overall_score,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
    allow_nil: true

  scope :latest_first, -> { order(created_at: :desc) }

  def complete!(failed_rules:)
    update!(
      status: failed_rules.positive? ? "completed_with_failures" : "completed",
      failed_rule_count: failed_rules,
      completed_at: Time.current
    )
  end

  def fail!(failed_rules:)
    update!(
      status: "failed",
      failed_rule_count: failed_rules,
      completed_at: Time.current
    )
  end
end
