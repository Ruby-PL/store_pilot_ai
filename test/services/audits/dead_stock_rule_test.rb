require "test_helper"

module Audits
  class DeadStockRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = DeadStockRule.new
    end

    test "returns nil when there are no synced products" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when stocked products are recent" do
      create_product!(shopify_product_id: "gid://shopify/Product/recent", captured_at: 10.days.ago)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects products with no sales signal for 90 and 180 days" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/stale",
        title: "Stale Hoodie",
        price: BigDecimal("25"),
        inventory_quantity: 4,
        captured_at: 100.days.ago
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/critical",
        title: "Old Backpack",
        price: BigDecimal("50"),
        inventory_quantity: 3,
        captured_at: 190.days.ago
      )

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "dead_stock", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "revenue", result.category
      assert_equal "Dead stock opportunities found", result.title
      assert_includes result.description, "$250.00"
      assert_includes result.recommendation, "clearance discount"
      assert_equal 2, result.details.fetch(:issue_count)
      assert_equal 2, result.details.fetch(:no_sales_90_day_count)
      assert_equal 1, result.details.fetch(:no_sales_180_day_count)
      assert_equal "250.0", result.details.fetch(:estimated_tied_up_value)
      assert_equal 2, result.details.fetch(:affected_products).size
      assert_equal [ "gid://shopify/Product/stale", "gid://shopify/Product/critical" ], result.details.fetch(:affected_product_ids)
    end

    test "ignores out of stock products" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/out",
        inventory_quantity: 0,
        captured_at: 190.days.ago
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "persists dead stock audit result through audit runner" do
      create_product!(shopify_product_id: "gid://shopify/Product/stale", captured_at: 100.days.ago)

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "dead_stock", result.rule_key
      assert_equal [ "gid://shopify/Product/stale" ], result.details.fetch("affected_product_ids")
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
  end
end
