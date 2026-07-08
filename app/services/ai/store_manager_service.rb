module Ai
  class StoreManagerService
    FALLBACK_RESPONSE = "I could not generate an AI answer right now. Your question was saved, and you can try again shortly."

    def self.call(...)
      new(...).call
    end

    def initialize(store:, question:, conversation: nil, provider: OpenaiProvider.new)
      @store = store
      @question = question.to_s.squish
      @conversation = conversation
      @provider = provider
    end

    def call
      raise ArgumentError, "question can't be blank" if question.blank?

      if SalesDropResponder.matches?(question)
        SalesDropResponder.call(store:, question:, conversation: current_conversation, provider:)
      elsif PrioritizationResponder.matches?(question)
        PrioritizationResponder.call(store:, question:, conversation: current_conversation, provider:)
      elsif InventoryReorderResponder.matches?(question)
        InventoryReorderResponder.call(store:, question:, conversation: current_conversation, provider:)
      elsif PromotionResponder.matches?(question)
        PromotionResponder.call(store:, question:, conversation: current_conversation, provider:)
      else
        conversation = current_conversation
        conversation.ai_messages.create!(role: "user", content: question)
        return blocked_conversation(conversation) unless store.consume_ai_request!

        response = provider.complete_recommendation(context: provider_context)
        conversation.ai_messages.create!(
          role: "assistant",
          content: response.text,
          prompt_tokens: response.prompt_tokens,
          completion_tokens: response.completion_tokens,
          total_tokens: response.total_tokens
        )
        Rails.logger.info("AI Store Manager response generated store_id=#{store.id} conversation_id=#{conversation.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
        conversation
      end
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "ai_store_manager" })
      fallback_conversation = current_conversation
      fallback_conversation.ai_messages.create!(role: "user", content: question) unless fallback_conversation.ai_messages.where(role: "user", content: question).exists?
      fallback_conversation.ai_messages.create!(role: "assistant", content: FALLBACK_RESPONSE)
      fallback_conversation
    end

    private

    attr_reader :store, :question, :conversation, :provider

    def current_conversation
      @current_conversation ||= conversation || store.ai_conversations.create!(title: question.truncate(80))
    end

    def provider_context
      {
        task: "Answer the merchant question using only the structured store context. If data is insufficient, say so clearly.",
        question:,
        store_context: StoreContextBuilder.call(store)
      }
    end

    def blocked_conversation(conversation)
      conversation.ai_messages.create!(role: "assistant", content: store.ai_usage_limit_message)
      Rails.logger.info("AI Store Manager request blocked by usage limit store_id=#{store.id} conversation_id=#{conversation.id}")
      conversation
    end
  end
end
