require "test_helper"

module Audits
  class RepeatBuyerAnalysisRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = RepeatBuyerAnalysisRule.new
    end

    test "returns nil without enough current customers" do
      create_order(customer: "A", processed_at: Date.new(2026, 6, 20))
      create_order(customer: "B", processed_at: Date.new(2026, 6, 21))

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when repeat buyer ratio is healthy" do
      create_order(customer: "A", processed_at: Date.new(2026, 5, 5))
      create_order(customer: "B", processed_at: Date.new(2026, 5, 6))
      create_order(customer: "C", processed_at: Date.new(2026, 5, 7))
      create_order(customer: "A", processed_at: Date.new(2026, 6, 20))
      create_order(customer: "B", processed_at: Date.new(2026, 6, 21))
      create_order(customer: "D", processed_at: Date.new(2026, 6, 22))

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects high first-time buyer ratio and repeat buyer drop" do
      create_order(customer: "A", processed_at: Date.new(2026, 5, 5))
      create_order(customer: "B", processed_at: Date.new(2026, 5, 6))
      create_order(customer: "C", processed_at: Date.new(2026, 5, 7))
      create_order(customer: "A", processed_at: Date.new(2026, 5, 25))
      create_order(customer: "B", processed_at: Date.new(2026, 5, 26))
      create_order(customer: "D", processed_at: Date.new(2026, 7, 1))
      create_order(customer: "E", processed_at: Date.new(2026, 7, 2))
      create_order(customer: "F", processed_at: Date.new(2026, 7, 3))
      create_order(customer: "G", processed_at: Date.new(2026, 7, 4))

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "repeat_buyer_analysis", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "revenue", result.category
      assert_equal "Repeat buyer retention risk found", result.title
      assert_includes result.description, "Current first-time buyer ratio is 100%"
      assert_includes result.recommendation, "retention offers"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal 30, result.details.fetch(:period_days)
      assert_equal 1.0, result.details.fetch(:current_period).fetch(:first_time_buyer_ratio)
      assert_equal 0.0, result.details.fetch(:current_period).fetch(:repeat_buyer_ratio)
      assert_equal(-0.33, result.details.fetch(:trend).fetch(:repeat_buyer_ratio_delta))
    end

    test "persists repeat buyer analysis through audit runner" do
      create_order(customer: "A", processed_at: Date.new(2026, 5, 5))
      create_order(customer: "B", processed_at: Date.new(2026, 5, 6))
      create_order(customer: "A", processed_at: Date.new(2026, 5, 25))
      create_order(customer: "C", processed_at: Date.new(2026, 6, 20))
      create_order(customer: "D", processed_at: Date.new(2026, 6, 21))
      create_order(customer: "E", processed_at: Date.new(2026, 6, 22))

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "repeat_buyer_analysis", result.rule_key
      assert_equal "medium", result.priority
      assert_equal "revenue", result.category
    end

    private

    def create_order(customer:, processed_at:)
      @store.order_snapshots.create!(
        shopify_order_id: "gid://shopify/Order/#{SecureRandom.hex(4)}",
        shopify_customer_id: "gid://shopify/Customer/#{customer}",
        total_price: BigDecimal("25"),
        currency: "EUR",
        processed_at: processed_at.in_time_zone,
        captured_at: Time.current
      )
    end
  end
end
