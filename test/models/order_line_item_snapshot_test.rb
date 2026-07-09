require "test_helper"

class OrderLineItemSnapshotTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    @order_snapshot = @store.order_snapshots.create!(
      shopify_order_id: "gid://shopify/Order/1",
      currency: "EUR",
      processed_at: Time.current,
      captured_at: Time.current
    )
  end

  test "belongs to an order snapshot and store" do
    line_item = @order_snapshot.order_line_item_snapshots.create!(
      store: @store,
      shopify_line_item_id: "gid://shopify/LineItem/1",
      shopify_product_id: "gid://shopify/Product/1",
      product_title: "Canvas Tote",
      quantity: 2,
      unit_price: BigDecimal("12.50"),
      captured_at: Time.current
    )

    assert_equal @order_snapshot, line_item.order_snapshot
    assert_equal @store, line_item.store
    assert_equal "gid://shopify/Product/1", line_item.shopify_product_id
  end

  test "requires product and quantity fields" do
    line_item = OrderLineItemSnapshot.new(
      quantity: 0,
      unit_price: -1,
      refunded_quantity: -1,
      refunded_amount: -1
    )

    assert_not line_item.valid?
    assert_includes line_item.errors[:order_snapshot], "must exist"
    assert_includes line_item.errors[:store], "must exist"
    assert_includes line_item.errors[:shopify_line_item_id], "can't be blank"
    assert_includes line_item.errors[:shopify_product_id], "can't be blank"
    assert_includes line_item.errors[:product_title], "can't be blank"
    assert_includes line_item.errors[:quantity], "must be greater than 0"
    assert_includes line_item.errors[:unit_price], "must be greater than or equal to 0"
    assert_includes line_item.errors[:refunded_quantity], "must be greater than or equal to 0"
    assert_includes line_item.errors[:refunded_amount], "must be greater than or equal to 0"
  end
end
