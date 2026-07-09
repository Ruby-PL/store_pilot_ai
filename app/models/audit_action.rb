class AuditAction < ApplicationRecord
  STATUSES = %w[open completed].freeze

  belongs_to :audit_run
  belongs_to :audit_result

  validates :title, :next_step, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audit_result_id, uniqueness: true

  scope :open_first, -> { order(Arel.sql("CASE status WHEN 'open' THEN 0 ELSE 1 END"), created_at: :asc) }

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end
end
