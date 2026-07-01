class AuditResult < ApplicationRecord
  STATUSES = %w[passed warning failed].freeze
  SEVERITIES = %w[low medium high].freeze

  belongs_to :audit_run

  validates :rule_key, :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }, allow_blank: true
end
