require "test_helper"

module Ai
  class SalesDropResponderTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "builds revenue drop context with likely causes" do
      audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 2)
      create_revenue_opportunity(audit_run, "top_customer_silence", "High-value customers have gone silent.")
      create_revenue_opportunity(audit_run, "underperforming_product", "Underperforming stocked products found.")
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Revenue is down because repeat buyers have gone silent and some products are underperforming. Review win-back and promotion.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 9,
          completion_tokens: 6,
          total_tokens: 15
        )
      )

      conversation = SalesDropResponder.call(
        store: @store,
        question: "Why are sales down?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "Why are sales down?", messages.first.content
      assert_equal "Revenue is down because repeat buyers have gone silent and some products are underperforming. Review win-back and promotion.", messages.second.content
      assert_equal "Why are sales down?", provider.context.fetch(:question)
      assert_includes provider.context.fetch(:likely_causes), "High-value customers have gone silent."
      assert_includes provider.context.fetch(:likely_causes), "Some stocked products are underperforming."
      assert_equal "north-pine.myshopify.com", provider.context.dig(:store_context, :store, :shopify_domain)
    end

    test "stores fallback when there is not enough data" do
      conversation = SalesDropResponder.call(
        store: @store,
        question: "Why are sales down?",
        provider: FailingProvider.new
      )

      assert_match(/not enough recent sales data/i, conversation.ai_messages.order(:created_at).last.content)
    end

    private

    def create_revenue_opportunity(audit_run, rule_key, title)
      audit_run.audit_results.create!(
        rule_key:,
        title:,
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score: 22,
        recommendation: "Review the issue.",
        details: { issue_count: 1 }
      )
    end

    class StaticProvider
      attr_reader :context

      def initialize(response)
        @response = response
      end

      def complete_recommendation(context:)
        @context = context
        @response
      end
    end

    class FailingProvider
      def complete_recommendation(context:)
        raise "provider failed"
      end
    end
  end
end
