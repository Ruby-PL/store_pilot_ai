require "test_helper"

module Ai
  class StoreContextBuilderTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret",
        name: "North Pine",
        currency: "EUR",
        products_count: 2,
        orders_count: 4,
        orders_total_price: BigDecimal("120"),
        products_synced_at: 1.hour.ago,
        orders_synced_at: 30.minutes.ago
      )
    end

    test "builds structured store, audit, revenue, product and inventory context" do
      create_product("A", inventory_quantity: 0)
      create_product("B", inventory_quantity: 2)
      audit_run = @store.audit_runs.create!(
        status: "completed",
        started_at: Time.current,
        completed_at: Time.current,
        overall_score: 74,
        category_scores: { revenue: 60 }
      )
      audit_run.audit_results.create!(
        rule_key: "bundle_opportunity",
        title: "Bundle opportunities found",
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        opportunity_score: 22,
        description: "Products bought together.",
        recommendation: "Test a bundle.",
        details: {
          issue_count: 1,
          affected_product_ids: [ "gid://shopify/Product/A" ],
          raw_shopify_payload: { email: "customer@example.com" }
        }
      )

      context = StoreContextBuilder.call(@store)

      assert_equal "north-pine.myshopify.com", context.dig(:store, :shopify_domain)
      assert_equal 74, context.dig(:latest_audit, :overall_score)
      assert_equal "bundle_opportunity", context.dig(:top_revenue_opportunities, 0, :rule_key)
      assert_equal 2, context.dig(:inventory_summary, :product_count)
      assert_equal 1, context.dig(:inventory_summary, :out_of_stock_count)
      assert_includes context.fetch(:product_summary).map { |product| product.fetch(:shopify_product_id) }, "gid://shopify/Product/A"
      assert_operator context.dig(:meta, :estimated_tokens), :>, 0
      assert_not_includes context.to_json, "customer@example.com"
      assert_not_includes context.to_json, "raw_shopify_payload"
    end

    test "limits context size collections" do
      12.times { |index| create_product(index.to_s, inventory_quantity: index) }

      context = StoreContextBuilder.call(@store)

      assert_equal 8, context.fetch(:product_summary).size
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
  end
end
