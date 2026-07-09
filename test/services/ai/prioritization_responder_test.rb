require "test_helper"

module Ai
  class PrioritizationResponderTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "builds top three recommended actions from latest opportunities" do
      audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 3)
      create_revenue_result(audit_run, "bundle_opportunity", "Bundle opportunities found", 32, [ "gid://shopify/Product/1" ])
      create_revenue_result(audit_run, "top_customer_silence", "High-value customers have gone silent", 28, [], [ "gid://shopify/Customer/1" ])
      create_revenue_result(audit_run, "underperforming_product", "Underperforming stocked products found", 26, [ "gid://shopify/Product/3" ])

      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "1. Focus on bundles. 2. Win back silent customers. 3. Fix underperforming products.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 10,
          completion_tokens: 8,
          total_tokens: 18
        )
      )

      conversation = PrioritizationResponder.call(
        store: @store,
        question: "What should I fix first?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "What should I fix first?", messages.first.content
      assert_equal "1. Focus on bundles. 2. Win back silent customers. 3. Fix underperforming products.", messages.second.content
      assert_equal "What should I fix first?", provider.context.fetch(:question)
      assert_equal 3, provider.context.fetch(:latest_opportunities).size
      assert_equal "bundle_opportunity", provider.context.fetch(:latest_opportunities).first.fetch(:rule_key)
    end

    test "falls back when no opportunities exist" do
      conversation = PrioritizationResponder.call(
        store: @store,
        question: "What should I fix first?",
        provider: FailingProvider.new
      )

      assert_match(/highest-scoring revenue opportunities/i, conversation.ai_messages.order(:created_at).last.content)
    end

    private

    def create_revenue_result(audit_run, rule_key, title, opportunity_score, affected_products = [], affected_customers = [])
      audit_run.audit_results.create!(
        rule_key:,
        title:,
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score:,
        recommendation: "Review this opportunity.",
        details: {
          affected_product_ids: affected_products,
          affected_customer_ids: affected_customers
        }
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
