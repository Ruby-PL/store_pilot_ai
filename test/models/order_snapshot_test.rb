require "test_helper"

class OrderSnapshotTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "belongs to a store and stores order snapshot fields" do
    processed_at = Time.zone.local(2026, 6, 24, 10, 15)
    captured_at = Time.zone.local(2026, 6, 25, 9, 0)

    snapshot = @store.order_snapshots.create!(
      shopify_order_id: "gid://shopify/Order/123",
      total_price: BigDecimal("42.50"),
      currency: "EUR",
      processed_at:,
      captured_at:
    )

    assert_equal @store, snapshot.store
    assert_equal "gid://shopify/Order/123", snapshot.shopify_order_id
    assert_equal BigDecimal("42.50"), snapshot.total_price
    assert_equal "EUR", snapshot.currency
    assert_equal processed_at, snapshot.processed_at
    assert_equal captured_at, snapshot.captured_at
  end

  test "requires core snapshot fields" do
    snapshot = OrderSnapshot.new

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:store], "must exist"
    assert_includes snapshot.errors[:shopify_order_id], "can't be blank"
    assert_includes snapshot.errors[:currency], "can't be blank"
    assert_includes snapshot.errors[:processed_at], "can't be blank"
    assert_includes snapshot.errors[:captured_at], "can't be blank"
  end

  test "requires valid numeric and currency values" do
    snapshot = @store.order_snapshots.build(
      shopify_order_id: "gid://shopify/Order/123",
      total_price: -1,
      currency: "EURO",
      processed_at: Time.current,
      captured_at: Time.current
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:total_price], "must be greater than or equal to 0"
    assert_includes snapshot.errors[:currency], "is the wrong length (should be 3 characters)"
  end

  test "store destroy removes order snapshots" do
    snapshot = @store.order_snapshots.create!(
      shopify_order_id: "gid://shopify/Order/123",
      currency: "EUR",
      processed_at: Time.current,
      captured_at: Time.current
    )

    @store.destroy!

    assert_not OrderSnapshot.exists?(snapshot.id)
  end
end
