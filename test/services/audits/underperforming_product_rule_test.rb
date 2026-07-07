require "test_helper"

module Audits
  class UnderperformingProductRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = UnderperformingProductRule.new
    end

    test "returns nil without enough stocked products" do
      create_product!("A", inventory_quantity: 5)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when catalog sales average is too low" do
      create_product!("A", inventory_quantity: 5)
      create_product!("B", inventory_quantity: 5)
      create_order_with_products("A")

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects stocked products with no sales below catalog average" do
      create_product!("A", title: "Best Seller", inventory_quantity: 2, price: "20")
      create_product!("B", title: "Slow Tote", inventory_quantity: 8, price: "15")
      create_product!("C", title: "Slow Pouch", inventory_quantity: 6, price: "10")
      8.times { create_order_with_products("A") }

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "underperforming_product", result.rule_key
      assert_equal "warning", result.status
      assert_equal "medium", result.severity
      assert_equal "revenue", result.category
      assert_equal "Underperforming stocked products found", result.title
      assert_includes result.recommendation, "discount or bundle placement"
      assert_equal 2, result.details.fetch(:issue_count)
      assert_equal 2.67, result.details.fetch(:catalog_average_units_sold)
      assert_equal "180.0", result.details.fetch(:estimated_tied_up_value)
      assert_equal(
        [ "gid://shopify/Product/B", "gid://shopify/Product/C" ],
        result.details.fetch(:affected_product_ids)
      )

      underperformer = result.details.fetch(:underperforming_products).first
      assert_equal "gid://shopify/Product/B", underperformer.fetch(:shopify_product_id)
      assert_equal "Slow Tote", underperformer.fetch(:title)
      assert_equal 0, underperformer.fetch(:units_sold)
      assert_equal 8, underperformer.fetch(:inventory_quantity)
    end

    test "uses latest product snapshot per product" do
      create_product!("A", inventory_quantity: 10, captured_at: 2.days.ago)
      create_product!("A", inventory_quantity: 0, captured_at: 1.day.ago)
      create_product!("B", inventory_quantity: 5)
      6.times { create_order_with_products("B") }

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "persists underperforming result through audit runner with priority" do
      create_product!("A", inventory_quantity: 2, price: "20")
      create_product!("B", inventory_quantity: 8, price: "15")
      create_product!("C", inventory_quantity: 6, price: "10")
      8.times { create_order_with_products("A") }

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "underperforming_product", result.rule_key
      assert_equal "medium", result.priority
      assert_equal "revenue", result.category
      assert_equal "medium", result.impact
    end

    private

    def create_product!(suffix, title: "Product #{suffix}", inventory_quantity:, price: "10", captured_at: Time.current)
      @store.product_snapshots.create!(
        shopify_product_id: "gid://shopify/Product/#{suffix}",
        title:,
        inventory_quantity:,
        price: BigDecimal(price),
        status: "ACTIVE",
        captured_at:
      )
    end

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
