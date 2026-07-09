require "test_helper"

module Ai
  class PromotionResponderTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "returns products to promote from sales, bundles and underperformance" do
      audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 2)
      create_product("A", inventory_quantity: 10)
      create_product("B", inventory_quantity: 8)
      create_product("C", inventory_quantity: 6)
      create_sales("A", 12)
      create_sales("B", 6)
      create_sales("C", 1)
      create_bundle_opportunity(audit_run, %w[A B], 4)
      create_underperforming_result(audit_run, "C", 1)

      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Promote A, B, and C.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 8,
          completion_tokens: 5,
          total_tokens: 13
        )
      )

      conversation = PromotionResponder.call(
        store: @store,
        question: "Which products to promote?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "Which products to promote?", messages.first.content
      assert_equal "Promote A, B, and C.", messages.second.content
      assert_equal 3, provider.context.fetch(:promotion_candidates).size
      assert_equal "gid://shopify/Product/A", provider.context.fetch(:promotion_candidates).first.fetch(:shopify_product_id)
      assert_includes provider.context.fetch(:task), "inventory constraints"
    end

    test "falls back without inventing availability or supplier detail" do
      conversation = PromotionResponder.call(
        store: @store,
        question: "What should I promote?",
        provider: FailingProvider.new
      )

      assert_match(/strongest in-stock best sellers/i, conversation.ai_messages.order(:created_at).last.content)
      refute_match(/lead times/i, conversation.ai_messages.order(:created_at).last.content)
    end

    private

    def create_product(suffix, inventory_quantity:)
      @store.product_snapshots.create!(
        shopify_product_id: "gid://shopify/Product/#{suffix}",
        title: "Product #{suffix}",
        inventory_quantity:,
        price: BigDecimal("10"),
        image_count: 1,
        status: "ACTIVE",
        captured_at: Time.current
      )
    end

    def create_sales(product_suffix, quantity)
      order = @store.order_snapshots.create!(
        shopify_order_id: "gid://shopify/Order/#{SecureRandom.hex(4)}",
        currency: "EUR",
        processed_at: Time.current,
        captured_at: Time.current
      )
      order.order_line_item_snapshots.create!(
        store: @store,
        shopify_line_item_id: "gid://shopify/LineItem/#{SecureRandom.hex(4)}",
        shopify_product_id: "gid://shopify/Product/#{product_suffix}",
        product_title: "Product #{product_suffix}",
        quantity:,
        unit_price: BigDecimal("10"),
        captured_at: Time.current
      )
    end

    def create_bundle_opportunity(audit_run, product_suffixes, frequency)
      audit_run.audit_results.create!(
        rule_key: "bundle_opportunity",
        title: "Bundle opportunities found",
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score: 22,
        recommendation: "Test a bundle.",
        details: {
          bundle_pairs: [
            {
              "product_ids" => product_suffixes.map { |suffix| "gid://shopify/Product/#{suffix}" },
              "frequency" => frequency
            }
          ]
        }
      )
    end

    def create_underperforming_result(audit_run, suffix, units_sold)
      audit_run.audit_results.create!(
        rule_key: "underperforming_product",
        title: "Underperforming stocked products found",
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score: 22,
        recommendation: "Review pricing.",
        details: {
          underperforming_products: [
            {
              "shopify_product_id" => "gid://shopify/Product/#{suffix}",
              "units_sold" => units_sold
            }
          ]
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
