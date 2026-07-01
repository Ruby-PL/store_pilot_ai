require "test_helper"

module Audits
  class ProductQualityRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = ProductQualityRule.new
    end

    test "returns nil when there are no synced products" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when products pass quality checks" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/healthy",
        title: "Everyday Canvas Tote",
        description: "A durable canvas tote with reinforced handles, interior pocket and a practical size for daily errands.",
        image_count: 2
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects missing descriptions, short descriptions, missing images and weak titles" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/missing-description",
        title: "Everyday Canvas Tote",
        description: nil,
        image_count: 1
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/short-description",
        title: "Weekend Backpack",
        description: "Small bag.",
        image_count: 1
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/no-image",
        title: "Trail Jacket",
        description: "A waterproof shell jacket with sealed seams and breathable fabric for wet commutes.",
        image_count: 0
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/weak-title",
        title: "Product",
        description: "A soft cotton t-shirt with a regular fit, reinforced collar and everyday styling.",
        image_count: 1
      )

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "product_quality", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "product_quality", result.category
      assert_equal "Product catalog quality issues found", result.title
      assert_includes result.description, "4 product quality issues"
      assert_includes result.recommendation, "Add clear product descriptions."
      assert_includes result.recommendation, "Expand short descriptions"
      assert_includes result.recommendation, "Add at least one product image."
      assert_includes result.recommendation, "Rewrite missing or generic product titles"
      assert_equal 4, result.details.fetch(:issue_count)
      assert_equal 1, result.details.fetch(:missing_description_count)
      assert_equal 1, result.details.fetch(:short_description_count)
      assert_equal 1, result.details.fetch(:missing_image_count)
      assert_equal 1, result.details.fetch(:weak_title_count)
      assert_equal 4, result.details.fetch(:affected_product_ids).size
    end

    test "uses the latest snapshot per Shopify product" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        title: "Product",
        description: nil,
        image_count: 0,
        captured_at: 2.days.ago
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        title: "Everyday Canvas Tote",
        description: "A durable canvas tote with reinforced handles, interior pocket and a practical size for daily errands.",
        image_count: 2,
        captured_at: 1.day.ago
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "persists product quality audit result through audit runner" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/no-image",
        title: "Trail Jacket",
        description: "A waterproof shell jacket with sealed seams and breathable fabric for wet commutes.",
        image_count: 0
      )

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "product_quality", result.rule_key
      assert_equal "warning", result.status
      assert_equal [ "gid://shopify/Product/no-image" ], result.details.fetch("affected_product_ids")
    end

    private

    def create_product!(captured_at: Time.current, **attributes)
      @store.product_snapshots.create!(
        {
          price: BigDecimal("10"),
          inventory_quantity: 1,
          status: "ACTIVE",
          captured_at:
        }.merge(attributes)
      )
    end
  end
end
