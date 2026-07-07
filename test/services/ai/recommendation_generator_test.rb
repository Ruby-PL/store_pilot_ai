require "test_helper"

module Ai
  class RecommendationGeneratorTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = store.audit_runs.create!(started_at: Time.current)
      @result = @audit_run.audit_results.create!(
        rule_key: "seo_gap",
        title: "SEO issue",
        status: "warning",
        severity: "medium",
        category: "seo",
        priority: "medium",
        impact: "medium",
        opportunity_score: 22,
        description: "Missing meta descriptions",
        recommendation: "Add meta descriptions.",
        details: {
          affected_product_ids: [ "gid://shopify/Product/1" ],
          raw_shopify_payload: { title: "Should not be sent" }
        }
      )
    end

    test "stores AI recommendation and token usage" do
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Add specific meta descriptions to your key products.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 10,
          completion_tokens: 7,
          total_tokens: 17
        )
      )

      RecommendationGenerator.call(@audit_run, provider:)

      @result.reload
      assert_equal "Add specific meta descriptions to your key products.", @result.ai_recommendation
      assert_equal "test", @result.ai_provider
      assert_equal "test-model", @result.ai_model
      assert_equal 10, @result.ai_prompt_tokens
      assert_equal 7, @result.ai_completion_tokens
      assert_equal 17, @result.ai_total_tokens
      assert_equal "SEO issue", provider.context.fetch(:title)
      assert_not_includes provider.context.to_json, "raw_shopify_payload"
    end

    test "falls back to non-AI recommendation when provider fails" do
      RecommendationGenerator.call(@audit_run, provider: FailingProvider.new)

      assert_equal "Add meta descriptions.", @result.reload.ai_recommendation
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
