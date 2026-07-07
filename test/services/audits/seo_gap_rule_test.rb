require "test_helper"

module Audits
  class SeoGapRuleTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      @audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)
      @rule = SeoGapRule.new
    end

    test "returns nil when there are no synced products" do
      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "returns nil when products pass SEO checks" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/healthy",
        seo_title: "Everyday Tote | North Pine",
        seo_description: "Shop a durable canvas tote for daily errands.",
        image_count: 2,
        image_alt_text_count: 2
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "detects missing meta titles, meta descriptions and image alt text" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/missing-title",
        seo_title: nil,
        seo_description: "Shop a durable canvas tote for daily errands.",
        image_count: 1,
        image_alt_text_count: 1
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/missing-description",
        seo_title: "Weekend Backpack | North Pine",
        seo_description: nil,
        image_count: 1,
        image_alt_text_count: 1
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/missing-alt-text",
        seo_title: "Trail Jacket | North Pine",
        seo_description: "Shop a waterproof shell jacket for wet commutes.",
        image_count: 2,
        image_alt_text_count: 1
      )

      result = @rule.call(store: @store, audit_run: @audit_run)

      assert_equal "seo_gap", result.rule_key
      assert_equal "warning", result.status
      assert_equal "high", result.severity
      assert_equal "seo", result.category
      assert_equal "Product SEO gaps found", result.title
      assert_includes result.description, "3 SEO gaps"
      assert_includes result.recommendation, "Add unique meta titles"
      assert_includes result.recommendation, "Add meta descriptions"
      assert_includes result.recommendation, "Add descriptive image alt text"
      assert_equal 3, result.details.fetch(:issue_count)
      assert_equal 1, result.details.fetch(:missing_meta_title_count)
      assert_equal 1, result.details.fetch(:missing_meta_description_count)
      assert_equal 1, result.details.fetch(:missing_image_alt_text_count)
      assert_equal 3, result.details.fetch(:affected_product_ids).size
    end

    test "does not flag alt text when product has no images" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/no-images",
        seo_title: "Gift Card | North Pine",
        seo_description: "Send a flexible store gift card.",
        image_count: 0,
        image_alt_text_count: 0
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "uses the latest snapshot per Shopify product" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        seo_title: nil,
        seo_description: nil,
        image_count: 1,
        image_alt_text_count: 0,
        captured_at: 2.days.ago
      )
      create_product!(
        shopify_product_id: "gid://shopify/Product/1",
        seo_title: "Everyday Tote | North Pine",
        seo_description: "Shop a durable canvas tote for daily errands.",
        image_count: 1,
        image_alt_text_count: 1,
        captured_at: 1.day.ago
      )

      assert_nil @rule.call(store: @store, audit_run: @audit_run)
    end

    test "persists SEO gap audit result through audit runner" do
      create_product!(
        shopify_product_id: "gid://shopify/Product/missing-title",
        seo_title: nil,
        seo_description: "Shop a durable canvas tote for daily errands.",
        image_count: 1,
        image_alt_text_count: 1
      )

      audit_run = AuditRunner.call(@store, rules: [ @rule ])
      result = audit_run.audit_results.sole

      assert_equal "completed", audit_run.status
      assert_equal "seo_gap", result.rule_key
      assert_equal "warning", result.status
      assert_equal [ "gid://shopify/Product/missing-title" ], result.details.fetch("affected_product_ids")
    end

    private

    def create_product!(captured_at: Time.current, **attributes)
      @store.product_snapshots.create!(
        {
          title: "Everyday Tote",
          description: "A durable canvas tote with reinforced handles and practical storage.",
          price: BigDecimal("10"),
          inventory_quantity: 1,
          status: "ACTIVE",
          captured_at:
        }.merge(attributes)
      )
    end
  end
end
