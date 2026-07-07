require "test_helper"

module Audits
  class DeadStockRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = DeadStockRule.new
    end

    test "returns nil when stocked products have sales" do
      create_product("A", inventory_quantity: 5)
      create_order_line_item("A")

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects stocked products without synced sales" do
      create_product("A", title: "Slow Tote", inventory_quantity: 8, price: "15")
      create_product("B", inventory_quantity: 2, price: "20")
      create_product("C", inventory_quantity: 5, price: "25")
      create_order_line_item("C")

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "dead_stock", result.rule_key
      assert_equal "warning", result.status
      assert_equal "medium", result.severity
      assert_equal "revenue", result.category
      assert_equal "Dead stock found", result.title
      assert_includes result.recommendation, "discounting"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal [ "gid://shopify/Product/A" ], result.details.fetch(:affected_product_ids)
      assert_equal "120.0", result.details.fetch(:estimated_tied_up_value)

      product = result.details.fetch(:dead_stock_products).sole
      assert_equal "Slow Tote", product.fetch(:title)
      assert_equal 8, product.fetch(:inventory_quantity)
    end

    test "persists dead stock through audit runner" do
      create_product("A", inventory_quantity: 8, price: "15")

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "dead_stock", result.rule_key
      assert_equal "medium", result.priority
      assert_equal "revenue", result.category
    end

    private

    def create_product(product, title: "Product #{product}", inventory_quantity:, price: "10")
      @store.product_snapshots.create!(
        shopify_product_id: "gid://shopify/Product/#{product}",
        title:,
        inventory_quantity:,
        price: BigDecimal(price),
        status: "ACTIVE",
        captured_at: Time.current
      )
    end

    def create_order_line_item(product)
      order = @store.order_snapshots.create!(
        shopify_order_id: "gid://shopify/Order/#{SecureRandom.hex(4)}",
        currency: "EUR",
        processed_at: Time.current,
        captured_at: Time.current
      )
      order.order_line_item_snapshots.create!(
        store: @store,
        shopify_line_item_id: "gid://shopify/LineItem/#{SecureRandom.hex(4)}",
        shopify_product_id: "gid://shopify/Product/#{product}",
        product_title: "Product #{product}",
        quantity: 1,
        unit_price: BigDecimal("10"),
        captured_at: Time.current
      )
    end
  end
end
