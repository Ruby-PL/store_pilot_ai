require "test_helper"

module Ai
  class StoreManagerServiceTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "builds context, calls provider and stores response token usage" do
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Fix the highest priority revenue opportunity first.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 11,
          completion_tokens: 7,
          total_tokens: 18
        )
      )

      conversation = StoreManagerService.call(
        store: @store,
        question: "What should I fix first?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "What should I fix first?", messages.first.content
      assert_equal "Fix the highest priority revenue opportunity first.", messages.second.content
      assert_equal 18, messages.second.total_tokens
      assert_equal "What should I fix first?", provider.context.fetch(:question)
      assert_equal "north-pine.myshopify.com", provider.context.dig(:store_context, :store, :shopify_domain)
    end

    test "stores graceful fallback when provider fails" do
      conversation = StoreManagerService.call(
        store: @store,
        question: "Why are sales down?",
        provider: FailingProvider.new
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "Why are sales down?", messages.first.content
      assert_match(/not enough recent sales data/i, messages.second.content)
      assert_equal 0, messages.second.total_tokens
    end

    test "routes sales drop questions through the sales drop responder" do
      audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      create_revenue_opportunity(audit_run, "top_customer_silence", "High-value customers have gone silent")
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Sales are down because repeat buyers are silent.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 8,
          completion_tokens: 5,
          total_tokens: 13
        )
      )

      conversation = StoreManagerService.call(
        store: @store,
        question: "Why are sales down?",
        provider:
      )

      assert_equal "Sales are down because repeat buyers are silent.", conversation.ai_messages.order(:created_at).second.content
      assert_includes provider.context.fetch(:likely_causes), "High-value customers have gone silent."
      assert_includes provider.context.fetch(:task), "If data is insufficient"
    end

    test "routes prioritization questions through the prioritization responder" do
      audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 3)
      create_revenue_opportunity(audit_run, "bundle_opportunity", "Bundle opportunities found", 32, [ "gid://shopify/Product/1" ])
      create_revenue_opportunity(audit_run, "top_customer_silence", "High-value customers have gone silent", 28, [], [ "gid://shopify/Customer/1" ])
      create_revenue_opportunity(audit_run, "underperforming_product", "Underperforming stocked products found", 26, [ "gid://shopify/Product/3" ])
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Start with bundles, then win back customers, then fix underperforming products.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 10,
          completion_tokens: 8,
          total_tokens: 18
        )
      )

      conversation = StoreManagerService.call(
        store: @store,
        question: "What should I fix first?",
        provider:
      )

      assert_equal "Start with bundles, then win back customers, then fix underperforming products.", conversation.ai_messages.order(:created_at).second.content
      assert_equal 3, provider.context.fetch(:latest_opportunities).size
      assert_equal "bundle_opportunity", provider.context.fetch(:latest_opportunities).first.fetch(:rule_key)
      assert_includes provider.context.fetch(:task), "top 3 actions"
    end

    test "routes reorder questions through the inventory reorder responder" do
      create_product("A", inventory_quantity: 0)
      create_product("B", inventory_quantity: 2)
      create_sales("A", 12)
      create_sales("B", 6)
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Reorder A and B.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 7,
          completion_tokens: 4,
          total_tokens: 11
        )
      )

      conversation = StoreManagerService.call(
        store: @store,
        question: "What inventory to reorder?",
        provider:
      )

      assert_equal "Reorder A and B.", conversation.ai_messages.order(:created_at).second.content
      assert_equal 2, provider.context.fetch(:reorder_candidates).size
      assert_includes provider.context.fetch(:task), "supplier lead times"
    end

    test "can append to an existing conversation" do
      conversation = @store.ai_conversations.create!(title: "Existing")

      StoreManagerService.call(
        store: @store,
        question: "What should I promote?",
        conversation:,
        provider: StaticProvider.new(RecommendationResponse.new(
          text: "Promote best sellers with stock.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 3,
          completion_tokens: 4,
          total_tokens: 7
        ))
      )

      assert_equal conversation, @store.ai_conversations.sole
      assert_equal 2, conversation.ai_messages.count
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

    def create_revenue_opportunity(audit_run, rule_key, title, opportunity_score = 22, affected_products = [], affected_customers = [])
      audit_run.audit_results.create!(
        rule_key:,
        title:,
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score:,
        recommendation: "Review the issue.",
        details: {
          issue_count: 1,
          affected_product_ids: affected_products,
          affected_customer_ids: affected_customers
        }
      )
    end

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
  end
end
