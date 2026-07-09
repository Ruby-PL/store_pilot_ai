require "test_helper"

module Ai
  class InventoryReorderResponderTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "returns top reorder candidates with confidence" do
      create_product("A", inventory_quantity: 0)
      create_product("B", inventory_quantity: 2)
      create_product("C", inventory_quantity: 4)
      create_sales("A", 12)
      create_sales("B", 6)
      create_sales("C", 1)

      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Reorder A first, then B, then C.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 8,
          completion_tokens: 5,
          total_tokens: 13
        )
      )

      conversation = InventoryReorderResponder.call(
        store: @store,
        question: "What inventory to reorder?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "What inventory to reorder?", messages.first.content
      assert_equal "Reorder A first, then B, then C.", messages.second.content
      assert_equal 3, provider.context.fetch(:reorder_candidates).size
      assert_equal "gid://shopify/Product/A", provider.context.fetch(:reorder_candidates).first.fetch(:shopify_product_id)
      assert_includes provider.context.fetch(:task), "do not guess supplier lead times"
    end

    test "falls back without inventing lead times" do
      conversation = InventoryReorderResponder.call(
        store: @store,
        question: "What should I reorder?",
        provider: FailingProvider.new
      )

      assert_match(/cannot infer supplier lead times/i, conversation.ai_messages.order(:created_at).last.content)
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
