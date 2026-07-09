require "test_helper"

module Audits
  class InventoryRiskRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = InventoryRiskRule.new
    end

    test "returns nil when there are no synced products" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when products have healthy stock" do
      create_product!(shopify_product_id: "gid://shopify/Product/healthy", inventory_quantity: 12)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects out of stock and low stock products" do
      create_product!(shopify_product_id: "gid://shopify/Product/out", inventory_quantity: 0)
      create_product!(shopify_product_id: "gid://shopify/Product/low", inventory_quantity: 2)
      create_product!(shopify_product_id: "gid://shopify/Product/healthy", inventory_quantity: 9)

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "inventory_risk", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "inventory", result.category
      assert_equal "Inventory risks found", result.title
      assert_includes result.description, "2 inventory risks"
      assert_includes result.recommendation, "Restock or hide out-of-stock products"
      assert_includes result.recommendation, "Review low-stock products"
      assert_equal 2, result.details.fetch(:issue_count)
      assert_equal 1, result.details.fetch(:out_of_stock_count)
      assert_equal 1, result.details.fetch(:low_stock_count)
      assert_equal "high", result.details.fetch(:stockout_risk_level)
      assert_equal [ "gid://shopify/Product/out", "gid://shopify/Product/low" ], result.details.fetch(:affected_product_ids)
    end

    test "flags low stock products as fast selling when recent order velocity is high" do
      create_product!(shopify_product_id: "gid://shopify/Product/low", inventory_quantity: 5)
      30.times { |index| create_order!(shopify_order_id: "gid://shopify/Order/#{index}") }

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "high", result.severity
      assert_equal 30, result.details.fetch(:recent_order_count)
      assert_equal 1, result.details.fetch(:fast_selling_low_stock_count)
      assert_includes result.recommendation, "recent order velocity is high"
    end

    test "uses the latest snapshot per Shopify product" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        inventory_quantity: 0,
        captured_at: 2.days.ago
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        inventory_quantity: 8,
        captured_at: 1.day.ago
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "persists inventory risk audit result through audit runner" do
      create_product!(shopify_product_id: "gid://shopify/Product/out", inventory_quantity: 0)

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "inventory_risk", result.rule_key
      assert_equal "warning", result.status
      assert_equal [ "gid://shopify/Product/out" ], result.details.fetch("affected_product_ids")
    end

    private

    def create_product!(captured_at: Time.current, **attributes)
      @store.product_snapshots.create!(
        {
          title: "Everyday Canvas Tote",
          price: BigDecimal("10"),
          inventory_quantity: 1,
          status: "ACTIVE",
          captured_at:
        }.merge(attributes)
      )
    end

    def create_order!(processed_at: Time.current, **attributes)
      @store.order_snapshots.create!(
        {
          total_price: BigDecimal("25"),
          currency: "USD",
          processed_at:,
          captured_at: Time.current
        }.merge(attributes)
      )
    end
  end
end
