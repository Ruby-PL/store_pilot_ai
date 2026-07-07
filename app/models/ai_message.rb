class AiMessage < ApplicationRecord
  ROLES = %w[user assistant system].freeze

  belongs_to :ai_conversation, touch: true

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true
  validates :prompt_tokens, :completion_tokens, :total_tokens,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
