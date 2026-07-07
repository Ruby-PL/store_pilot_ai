require "test_helper"

module Audits
  class BundleOpportunityRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = BundleOpportunityRule.new
    end

    test "returns nil when there are no order line items" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "ignores low confidence pairs with too little data" do
      create_order_with_products("A", "B")
      create_order_with_products("A", "C")

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects frequently co-purchased product pairs" do
      4.times { create_order_with_products("A", "B") }
      create_order_with_products("A", "C")
      create_order_with_products("B", "C")

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "bundle_opportunity", result.rule_key
      assert_equal "warning", result.status
      assert_equal "medium", result.severity
      assert_equal "revenue", result.category
      assert_equal "Bundle opportunities found", result.title
      assert_includes result.recommendation, "bundle offer"
      assert_equal 1, result.details.fetch(:issue_count)

      pair = result.details.fetch(:bundle_pairs).sole
      assert_equal [ "gid://shopify/Product/A", "gid://shopify/Product/B" ], pair.fetch(:product_ids)
      assert_equal 4, pair.fetch(:frequency)
      assert_operator pair.fetch(:confidence), :>=, 0.4
      assert_equal [ "gid://shopify/Product/A", "gid://shopify/Product/B" ], result.details.fetch(:affected_product_ids)
    end

    test "persists bundle result through audit runner" do
      3.times { create_order_with_products("A", "B") }

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "bundle_opportunity", result.rule_key
      assert_equal "revenue", result.category
      assert_equal "medium", result.priority
    end

    private

    def create_order_with_products(*product_suffixes)
      order = @store.order_snapshots.create!(
        shopify_order_id: "gid://shopify/Order/#{SecureRandom.hex(4)}",
        currency: "EUR",
        processed_at: Time.current,
        captured_at: Time.current
      )

      product_suffixes.each do |suffix|
        order.order_line_item_snapshots.create!(
          store: @store,
          shopify_line_item_id: "gid://shopify/LineItem/#{SecureRandom.hex(4)}",
          shopify_product_id: "gid://shopify/Product/#{suffix}",
          product_title: "Product #{suffix}",
          quantity: 1,
          unit_price: BigDecimal("10"),
          captured_at: Time.current
        )
      end
    end
  end
end
