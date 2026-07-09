class AiConversation < ApplicationRecord
  belongs_to :store
  has_many :ai_messages, dependent: :destroy

  validates :title, presence: true

  scope :latest_first, -> { order(updated_at: :desc) }
end
