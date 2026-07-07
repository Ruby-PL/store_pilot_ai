require "test_helper"

module Ai
  class RevenueExplanationGeneratorTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      audit_run = store.audit_runs.create!(started_at: Time.current)
      @result = audit_run.audit_results.create!(
        rule_key: "bundle_opportunity",
        title: "Bundle opportunities found",
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        description: "Products are often bought together.",
        recommendation: "Test a bundle offer.",
        details: {
          issue_count: 1,
          affected_product_ids: [ "gid://shopify/Product/1" ],
          bundle_pairs: [ { product_ids: [ "gid://shopify/Product/1", "gid://shopify/Product/2" ], frequency: 4 } ],
          raw_shopify_payload: { email: "customer@example.com" }
        }
      )
    end

    test "stores revenue explanation and token usage from structured context" do
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "These products sell together. Test a bundle. Checklist: pick placement.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20
        )
      )

      RevenueExplanationGenerator.call(@result, provider:)

      @result.reload
      assert_equal "These products sell together. Test a bundle. Checklist: pick placement.", @result.ai_recommendation
      assert_equal "test", @result.ai_provider
      assert_equal "test-model", @result.ai_model
      assert_equal 12, @result.ai_prompt_tokens
      assert_equal 8, @result.ai_completion_tokens
      assert_equal 20, @result.ai_total_tokens
      assert_equal "Explain this revenue opportunity in plain English. Return a short explanation, suggested action, and optional checklist.", provider.context.fetch(:task)
      assert_equal [ "gid://shopify/Product/1" ], provider.context.dig(:details, "affected_product_ids")
      assert_not_includes provider.context.to_json, "customer@example.com"
      assert_not_includes provider.context.to_json, "raw_shopify_payload"
    end

    test "stores fallback text when provider fails" do
      RevenueExplanationGenerator.call(@result, provider: FailingProvider.new)

      assert_equal "Products are often bought together. Test a bundle offer.", @result.reload.ai_recommendation
      assert_equal 0, @result.ai_total_tokens
    end

    private

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
