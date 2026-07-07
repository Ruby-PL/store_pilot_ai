module Ai
  class RecommendationGenerator
    def self.call(...)
      new(...).call
    end

    def initialize(audit_run, provider: OpenaiProvider.new)
      @audit_run = audit_run
      @provider = provider
    end

    def call
      audit_run.audit_results.find_each do |result|
        generate_for(result)
      end
    end

    private

    attr_reader :audit_run, :provider

    def generate_for(result)
      return RevenueExplanationGenerator.call(result, provider:) if result.category == "revenue"

      response = provider.complete_recommendation(context: context_for(result))
      result.update!(
        ai_recommendation: response.text,
        ai_provider: response.provider,
        ai_model: response.model,
        ai_prompt_tokens: response.prompt_tokens,
        ai_completion_tokens: response.completion_tokens,
        ai_total_tokens: response.total_tokens
      )
      Rails.logger.info("AI recommendation generated audit_result_id=#{result.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { audit_run_id: audit_run.id, audit_result_id: result.id, source: "ai_recommendation" })
      result.update!(ai_recommendation: fallback_for(result))
    end

    def context_for(result)
      {
        rule_key: result.rule_key,
        title: result.title,
        category: result.category,
        priority: result.priority,
        impact: result.impact,
        severity: result.severity,
        description: result.description,
        recommendation: result.recommendation,
        details_summary: summarize_details(result.details)
      }
    end

    def summarize_details(details)
      (details || {}).slice(
        "issue_count",
        "affected_product_ids",
        "stockout_risk_level",
        "estimated_tied_up_value",
        "missing_review_data_count",
        "missing_review_count",
        "low_review_count"
      )
    end

    def fallback_for(result)
      result.recommendation.presence || "Review this #{result.category || 'operations'} opportunity and prioritize the highest-impact fixes first."
    end
  end
end
