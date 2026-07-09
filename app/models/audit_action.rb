class AuditAction < ApplicationRecord
  STATUSES = %w[open completed].freeze

  belongs_to :audit_run
  belongs_to :audit_result

  validates :title, :next_step, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audit_result_id, uniqueness: true
  validates :reference_url, length: { maximum: 2048 }, allow_blank: true

  scope :open_first, -> { order(Arel.sql("CASE status WHEN 'open' THEN 0 ELSE 1 END"), created_at: :asc) }
  scope :completed_first, -> { order(Arel.sql("CASE status WHEN 'completed' THEN 0 ELSE 1 END"), completed_at: :desc, created_at: :desc) }

  def complete!(merchant_note: nil, reference_url: nil)
    update!(
      status: "completed",
      completed_at: Time.current,
      merchant_note: merchant_note.presence,
      reference_url: reference_url.presence
    )
  end

  def update_tracking!(merchant_note: nil, reference_url: nil)
    update!(
      merchant_note: merchant_note.presence,
      reference_url: reference_url.presence
    )
  end
end
