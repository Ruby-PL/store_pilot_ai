module Ai
  class RevenueExplanationGenerator
    DETAIL_KEYS = %w[
      issue_count
      affected_product_ids
      affected_customer_ids
      estimated_tied_up_value
      estimated_lost_revenue
      bundle_pairs
      underperforming_products
      customer_summaries
      current_period
      previous_period
      trend
      return_rate_products
      price_elasticity_signals
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(result, provider:)
      @result = result
      @provider = provider
    end

    def call
      response = provider.complete_recommendation(context:)
      result.update!(
        ai_recommendation: response.text,
        ai_provider: response.provider,
        ai_model: response.model,
        ai_prompt_tokens: response.prompt_tokens,
        ai_completion_tokens: response.completion_tokens,
        ai_total_tokens: response.total_tokens
      )
      Rails.logger.info("AI revenue explanation generated audit_result_id=#{result.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { audit_result_id: result.id, source: "ai_revenue_explanation" })
      result.update!(ai_recommendation: fallback_text)
    end

    private

    attr_reader :result, :provider

    def context
      {
        task: "Explain this revenue opportunity in plain English. Return a short explanation, suggested action, and optional checklist.",
        rule_key: result.rule_key,
        title: result.title,
        priority: result.priority,
        impact: result.impact,
        severity: result.severity,
        description: result.description,
        recommendation: result.recommendation,
        details: structured_details
      }
    end

    def structured_details
      (result.details || {}).slice(*DETAIL_KEYS)
    end

    def fallback_text
      [
        result.description.presence || "A revenue opportunity was detected from the synced store data.",
        result.recommendation.presence || "Review the affected products or customers and choose the highest-impact next action."
      ].join(" ")
    end
  end
end
