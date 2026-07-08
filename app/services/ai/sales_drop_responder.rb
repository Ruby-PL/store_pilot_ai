module Ai
  class SalesDropResponder
    FALLBACK_RESPONSE = "There is not enough recent sales data to explain the drop with confidence yet. Review the latest revenue opportunities and recent order trends."
    SALES_DROP_PATTERNS = [
      /sales (are )?down/i,
      /revenue (is )?down/i,
      /sales decline/i,
      /revenue decline/i,
      /why are sales/i
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(store:, question:, conversation: nil, provider: OpenaiProvider.new)
      @store = store
      @question = question.to_s.squish
      @conversation = conversation
      @provider = provider
    end

    def self.matches?(question)
      SALES_DROP_PATTERNS.any? { |pattern| question.to_s.match?(pattern) }
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
      Rails.logger.info("AI sales drop response generated store_id=#{store.id} conversation_id=#{conversation.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
      conversation
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "ai_sales_drop" })
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
        task: "Explain why sales are down using only structured store context. If data is insufficient, say so clearly and suggest next actions.",
        question:,
        store_context: StoreContextBuilder.call(store),
        sales_summary: sales_summary,
        likely_causes: likely_causes
      }
    end

    def sales_summary
      {
        order_count: store.orders_count,
        total_revenue: store.orders_total_price.to_s,
        currency: store.orders_currency.presence || store.currency,
        last_sync_at: store.orders_synced_at&.iso8601
      }
    end

    def likely_causes
      causes = []
      causes << "High-value customers have gone silent." if revenue_opportunities.any? { |result| result.rule_key == "top_customer_silence" }
      causes << "Some stocked products are underperforming." if revenue_opportunities.any? { |result| result.rule_key == "underperforming_product" }
      causes << "Dead stock may be tying up inventory." if revenue_opportunities.any? { |result| result.rule_key == "dead_stock" }
      causes << "Bundle opportunities suggest missed cross-sell potential." if revenue_opportunities.any? { |result| result.rule_key == "bundle_opportunity" }
      causes.presence || [ "There is not enough revenue-opportunity data yet to explain the drop confidently." ]
    end

    def revenue_opportunities
      @revenue_opportunities ||= store.audit_runs.latest_first.includes(:audit_results).first&.audit_results&.select { |result| result.category == "revenue" } || []
    end

    def fallback_response
      if store.orders_count.to_i.zero? || store.orders_synced_at.blank?
        FALLBACK_RESPONSE
      else
        "#{FALLBACK_RESPONSE} Likely causes: #{likely_causes.join(' ')}"
      end
    end
  end
end
