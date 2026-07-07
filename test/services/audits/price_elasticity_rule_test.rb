require "test_helper"

module Audits
  class PriceElasticityRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = PriceElasticityRule.new
    end

    test "returns nil without enough product history" do
      create_snapshot("A", inventory_quantity: 0, captured_at: 4.days.ago)
      create_snapshot("A", inventory_quantity: 5, captured_at: 3.days.ago)
      create_snapshot("A", inventory_quantity: 0, captured_at: 1.day.ago)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil for single fast sellout" do
      create_sellout_cycle("A", restocked_at: 10.days.ago, sold_out_at: 6.days.ago)
      create_snapshot("A", inventory_quantity: 0, captured_at: 1.day.ago)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects repeated fast sellouts after restock" do
      create_sellout_cycle("A", restocked_at: 20.days.ago, sold_out_at: 16.days.ago)
      create_sellout_cycle("A", restocked_at: 10.days.ago, sold_out_at: 5.days.ago)

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "price_elasticity", result.rule_key
      assert_equal "warning", result.status
      assert_equal "medium", result.severity
      assert_equal "revenue", result.category
      assert_equal "Potential underpricing signals found", result.title
      assert_includes result.recommendation, "Do not automatically increase prices"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal [ "gid://shopify/Product/A" ], result.details.fetch(:affected_product_ids)

      signal = result.details.fetch(:price_elasticity_signals).sole
      assert_equal "medium", signal.fetch(:confidence)
      assert_equal 2, signal.fetch(:fast_sellout_count)
      assert_equal 2, signal.fetch(:sellout_windows).size
    end

    test "persists pricing signal through audit runner" do
      create_sellout_cycle("A", restocked_at: 30.days.ago, sold_out_at: 26.days.ago)
      create_sellout_cycle("A", restocked_at: 20.days.ago, sold_out_at: 16.days.ago)
      create_sellout_cycle("A", restocked_at: 10.days.ago, sold_out_at: 7.days.ago)

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "price_elasticity", result.rule_key
      assert_equal "high", result.priority
      assert_equal "revenue", result.category
    end

    private

    def create_sellout_cycle(product, restocked_at:, sold_out_at:)
      create_snapshot(product, inventory_quantity: 0, captured_at: restocked_at - 1.day)
      create_snapshot(product, inventory_quantity: 8, captured_at: restocked_at)
      create_snapshot(product, inventory_quantity: 0, captured_at: sold_out_at)
    end

    def create_snapshot(product, inventory_quantity:, captured_at:)
      @store.product_snapshots.create!(
        shopify_product_id: "gid://shopify/Product/#{product}",
        title: "Product #{product}",
        inventory_quantity:,
        price: BigDecimal("25"),
        status: "ACTIVE",
        captured_at:
      )
    end
  end
end
