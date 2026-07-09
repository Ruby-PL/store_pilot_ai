require "test_helper"

module Audits
  class ReviewGapRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = ReviewGapRule.new
    end

    test "returns nil when there are no synced products" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when products are below the sales threshold" do
      create_product!(shopify_product_id: "gid://shopify/Product/small", price: BigDecimal("10"), inventory_quantity: 5)

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects missing review data through placeholder integration" do
      create_product!(shopify_product_id: "gid://shopify/Product/high-value", price: BigDecimal("40"), inventory_quantity: 4)

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "review_gap", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "conversion", result.category
      assert_equal "Review coverage gaps found", result.title
      assert_includes result.recommendation, "Connect a reviews app integration"
      assert_equal 1, result.details.fetch(:issue_count)
      assert_equal "100.0", result.details.fetch(:sales_threshold)
      assert_equal "placeholder", result.details.fetch(:review_provider)
      assert_equal 1, result.details.fetch(:missing_review_data_count)
      assert_equal [ "gid://shopify/Product/high-value" ], result.details.fetch(:affected_product_ids)
    end

    test "detects missing and low reviews through a future provider interface" do
      missing = create_product!(shopify_product_id: "gid://shopify/Product/missing", price: BigDecimal("60"), inventory_quantity: 3)
      low = create_product!(shopify_product_id: "gid://shopify/Product/low", price: BigDecimal("80"), inventory_quantity: 2)
      healthy = create_product!(shopify_product_id: "gid://shopify/Product/healthy", price: BigDecimal("90"), inventory_quantity: 2)
      provider = StaticReviewProvider.new({
        missing.shopify_product_id => 0,
        low.shopify_product_id => 2,
        healthy.shopify_product_id => 8
      })

      result = ReviewGapRule.new(review_provider: provider).call(store: @store, audit_run: @audit_run)

      assert_equal "high", result.severity
      assert_includes result.recommendation, "Collect first reviews"
      assert_includes result.recommendation, "thin social proof"
      assert_equal 1, result.details.fetch(:missing_review_count)
      assert_equal 1, result.details.fetch(:low_review_count)
      assert_equal [ missing.shopify_product_id, low.shopify_product_id ], result.details.fetch(:affected_product_ids)
    end

    test "persists review gap audit result through audit runner" do
      create_product!(shopify_product_id: "gid://shopify/Product/high-value", price: BigDecimal("40"), inventory_quantity: 4)

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "review_gap", result.rule_key
      assert_equal [ "gid://shopify/Product/high-value" ], result.details.fetch("affected_product_ids")
    end

    private

    StaticReviewProvider = Data.define(:counts) do
      def review_count_for(snapshot)
        counts.fetch(snapshot.shopify_product_id)
      end
    end

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
