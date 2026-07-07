require "test_helper"

module Audits
  class TopCustomerSilenceRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = TopCustomerSilenceRule.new
    end

    test "returns nil without enough identifiable customers" do
      create_order(customer: "A", total_price: "100", processed_at: 90.days.ago)
      create_order(customer: "B", total_price: "80", processed_at: 90.days.ago)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when top customers ordered recently" do
      create_order(customer: "A", total_price: "300", processed_at: 10.days.ago)
      create_order(customer: "B", total_price: "100", processed_at: 90.days.ago)
      create_order(customer: "C", total_price: "80", processed_at: 90.days.ago)
      create_order(customer: "D", total_price: "60", processed_at: 90.days.ago)
      create_order(customer: "E", total_price: "40", processed_at: 90.days.ago)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects silent top customer and stores anonymized summary" do
      create_order(customer: "A", total_price: "200", processed_at: 120.days.ago)
      create_order(customer: "A", total_price: "100", processed_at: 100.days.ago)
      create_order(customer: "B", total_price: "100", processed_at: 10.days.ago)
      create_order(customer: "C", total_price: "80", processed_at: 10.days.ago)
      create_order(customer: "D", total_price: "60", processed_at: 10.days.ago)
      create_order(customer: "E", total_price: "40", processed_at: 10.days.ago)

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "top_customer_silence", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "revenue", result.category
      assert_equal "High-value customers have gone silent", result.title
      assert_includes result.recommendation, "win-back offer"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal "150.0", result.details.fetch(:estimated_lost_revenue)
      assert_equal [ "gid://shopify/Customer/A" ], result.details.fetch(:affected_customer_ids)

      summary = result.details.fetch(:customer_summaries).sole
      assert_equal "gid://shopify/Customer/A", summary.fetch(:shopify_customer_id)
      assert_equal 2, summary.fetch(:order_count)
      assert_equal "300.0", summary.fetch(:total_value)
      assert_equal "150.0", summary.fetch(:average_order_value)
      assert_operator summary.fetch(:days_since_last_order), :>=, 90
      assert_not summary.key?(:email)
      assert_not summary.key?(:name)
    end

    test "persists top customer silence result through audit runner with priority" do
      create_order(customer: "A", total_price: "300", processed_at: 90.days.ago)
      create_order(customer: "B", total_price: "100", processed_at: 10.days.ago)
      create_order(customer: "C", total_price: "80", processed_at: 10.days.ago)
      create_order(customer: "D", total_price: "60", processed_at: 10.days.ago)
      create_order(customer: "E", total_price: "40", processed_at: 10.days.ago)

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "top_customer_silence", result.rule_key
      assert_equal "high", result.priority
      assert_equal "revenue", result.category
      assert_equal "high", result.impact
    end

    private

    def create_order(customer:, total_price:, processed_at:)
      @store.order_snapshots.create!(
        shopify_order_id: "gid://shopify/Order/#{SecureRandom.hex(4)}",
        shopify_customer_id: "gid://shopify/Customer/#{customer}",
        total_price: BigDecimal(total_price),
        currency: "EUR",
        processed_at:,
        captured_at: Time.current
      )
    end
  end
end
