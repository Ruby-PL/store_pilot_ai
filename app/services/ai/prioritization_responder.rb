module Ai
  class PrioritizationResponder
    FALLBACK_RESPONSE = "Start with the highest-scoring revenue opportunities in the latest audit. Fix the issues with the biggest impact first, then work through the next two items."
    PRIORITIZATION_PATTERNS = [
      /what should i fix first/i,
      /what to fix first/i,
      /priorit/i,
      /where should i start/i
    ].freeze

    def self.call(...)
      new(...).call
    end

    def self.matches?(question)
      PRIORITIZATION_PATTERNS.any? { |pattern| question.to_s.match?(pattern) }
    end

    def initialize(store:, question:, conversation: nil, provider: OpenaiProvider.new)
      @store = store
      @question = question.to_s.squish
      @conversation = conversation
      @provider = provider
    end

    def call
      conversation = current_conversation
      conversation.ai_messages.create!(role: "user", content: question)
      response = provider.complete_recommendation(context: prompt_context)
      conversation.ai_messages.create!(
        role: "assistant",
        content: response.text,
        prompt_tokens: response.prompt_tokens,
        completion_tokens: response.completion_tokens,
        total_tokens: response.total_tokens
      )
      Rails.logger.info("AI prioritization response generated store_id=#{store.id} conversation_id=#{conversation.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
      conversation
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "ai_prioritization" })
      conversation.ai_messages.create!(role: "assistant", content: fallback_response)
      conversation
    end

    private

    attr_reader :store, :question, :conversation, :provider

    def current_conversation
      @current_conversation ||= conversation || store.ai_conversations.create!(title: question.truncate(80))
    end

    def prompt_context
      {
        task: "Recommend the top 3 actions to fix first using only structured store context. Explain why each matters and include affected products where relevant.",
        question:,
        latest_opportunities: ranked_opportunities,
        store_context: StoreContextBuilder.call(store)
      }
    end

    def ranked_opportunities
      latest_audit_results
        .sort_by { |result| [ -result.opportunity_score.to_i, result.created_at ] }
        .first(3)
        .map do |result|
          {
            rule_key: result.rule_key,
            title: result.title,
            priority: result.priority,
            impact: result.impact,
            severity: result.severity,
            opportunity_score: result.opportunity_score,
            recommendation: result.ai_recommendation.presence || result.recommendation,
            affected_product_ids: Array(result.details&.dig("affected_product_ids")).first(3),
            affected_customer_ids: Array(result.details&.dig("affected_customer_ids")).first(3)
          }
        end
    end

    def latest_audit_results
      @latest_audit_results ||= store.audit_runs.latest_first.includes(:audit_results).first&.audit_results&.reject { |result| result.status == "passed" } || []
    end

    def fallback_response
      opportunities = ranked_opportunities
      return FALLBACK_RESPONSE if opportunities.empty?

      lines = [ "Here is where to start:" ] +
        opportunities.map.with_index(1) do |opportunity, index|
          detail = opportunity.fetch(:recommendation).presence || opportunity.fetch(:title)
          products = Array(opportunity.fetch(:affected_product_ids)).presence
          suffix = products.present? ? " Affected products: #{products.join(', ')}." : ""
          "#{index}. #{detail}#{suffix}"
        end
      lines.join(" ")
    end
  end
end
