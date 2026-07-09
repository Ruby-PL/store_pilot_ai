require "test_helper"

module Audits
  class ReturnRateRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = ReturnRateRule.new
    end

    test "returns nil without enough refunded product data" do
      create_line_item(product: "A", quantity: 2, refunded_quantity: 1)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "flags products with high refund ratio" do
      create_line_item(product: "A", quantity: 4, refunded_quantity: 2, refunded_amount: "40")
      create_line_item(product: "B", quantity: 10, refunded_quantity: 1, refunded_amount: "10")

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "return_rate", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "revenue", result.category
      assert_equal "High refund ratio products found", result.title
      assert_includes result.recommendation, "product expectations"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal [ "gid://shopify/Product/A" ], result.details.fetch(:affected_product_ids)

      product = result.details.fetch(:return_rate_products).sole
      assert_equal "gid://shopify/Product/A", product.fetch(:shopify_product_id)
      assert_equal 4, product.fetch(:units_sold)
      assert_equal 2, product.fetch(:refunded_units)
      assert_equal 0.5, product.fetch(:refund_ratio)
    end

    test "persists return rate result through audit runner" do
      create_line_item(product: "A", quantity: 4, refunded_quantity: 1, refunded_amount: "20")

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "return_rate", result.rule_key
      assert_equal "medium", result.priority
      assert_equal "revenue", result.category
    end

    private

    def create_line_item(product:, quantity:, refunded_quantity:, refunded_amount: "0")
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
        quantity:,
        unit_price: BigDecimal("20"),
        refunded_quantity:,
        refunded_amount: BigDecimal(refunded_amount),
        captured_at: Time.current
      )
    end
  end
end
