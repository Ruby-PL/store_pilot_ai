require "test_helper"

class ProductSnapshotTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "belongs to a store and stores product snapshot fields" do
    captured_at = Time.zone.local(2026, 6, 25, 9, 0)

    snapshot = @store.product_snapshots.create!(
      shopify_product_id: "gid://shopify/Product/123",
      title: "Everyday Tote",
      description: "A practical canvas tote for daily errands.",
      image_count: 2,
      image_alt_text_count: 1,
      seo_title: "Everyday Tote | North Pine",
      seo_description: "Shop a durable canvas tote for daily errands.",
      price: BigDecimal("24.50"),
      inventory_quantity: 8,
      status: "active",
      captured_at:
    )

    assert_equal @store, snapshot.store
    assert_equal "gid://shopify/Product/123", snapshot.shopify_product_id
    assert_equal "Everyday Tote", snapshot.title
    assert_equal "A practical canvas tote for daily errands.", snapshot.description
    assert_equal 2, snapshot.image_count
    assert_equal 1, snapshot.image_alt_text_count
    assert_equal "Everyday Tote | North Pine", snapshot.seo_title
    assert_equal "Shop a durable canvas tote for daily errands.", snapshot.seo_description
    assert_equal BigDecimal("24.50"), snapshot.price
    assert_equal 8, snapshot.inventory_quantity
    assert_equal "active", snapshot.status
    assert_equal captured_at, snapshot.captured_at
  end

  test "requires core snapshot fields" do
    snapshot = ProductSnapshot.new

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:store], "must exist"
    assert_includes snapshot.errors[:shopify_product_id], "can't be blank"
    assert_includes snapshot.errors[:captured_at], "can't be blank"
  end

  test "requires non-negative numeric values" do
    snapshot = @store.product_snapshots.build(
      shopify_product_id: "gid://shopify/Product/123",
      title: "Everyday Tote",
      price: -1,
      inventory_quantity: -1,
      image_count: -1,
      image_alt_text_count: -1,
      captured_at: Time.current
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:price], "must be greater than or equal to 0"
    assert_includes snapshot.errors[:inventory_quantity], "must be greater than or equal to 0"
    assert_includes snapshot.errors[:image_count], "must be greater than or equal to 0"
    assert_includes snapshot.errors[:image_alt_text_count], "must be greater than or equal to 0"
  end

  test "allows blank title so audits can detect missing product titles" do
    snapshot = @store.product_snapshots.build(
      shopify_product_id: "gid://shopify/Product/123",
      title: "",
      captured_at: Time.current
    )

    assert_predicate snapshot, :valid?
  end

  test "store destroy removes product snapshots" do
    snapshot = @store.product_snapshots.create!(
      shopify_product_id: "gid://shopify/Product/123",
      title: "Everyday Tote",
      captured_at: Time.current
    )

    @store.destroy!

    assert_not ProductSnapshot.exists?(snapshot.id)
  end
end
