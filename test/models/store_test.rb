require "test_helper"

class StoreTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "merchant@example.com")
  end

  test "belongs to a user" do
    store = Store.new(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")

    assert_not store.valid?
    assert_includes store.errors[:user], "must exist"
  end

  test "normalizes Shopify domains" do
    store = @user.stores.create!(shopify_domain: "  NORTH-PINE.MYSHOPIFY.COM ", access_token: "shpat_secret")

    assert_equal "north-pine.myshopify.com", store.shopify_domain
  end

  test "requires a valid Shopify domain" do
    store = @user.stores.build(shopify_domain: "north-pine.example.com", access_token: "shpat_secret")

    assert_not store.valid?
    assert_includes store.errors[:shopify_domain], "is invalid"
  end

  test "Shopify domains are unique" do
    @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_first")
    duplicate = @user.stores.build(shopify_domain: "NORTH-PINE.MYSHOPIFY.COM", access_token: "shpat_second")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:shopify_domain], "has already been taken"
  end

  test "requires an access token" do
    store = @user.stores.build(shopify_domain: "north-pine.myshopify.com", access_token: nil)

    assert_not store.valid?
    assert_includes store.errors[:access_token], "can't be blank"
  end

  test "does not require an access token when inactive" do
    store = @user.stores.build(shopify_domain: "north-pine.myshopify.com", access_token: nil, active: false)

    assert_predicate store, :valid?
  end

  test "tracks monthly AI usage by plan" do
    store = @user.stores.create!(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      ai_plan: "pro",
      ai_requests_count: 2,
      ai_requests_counted_on: Time.current.beginning_of_month.to_date
    )

    assert_equal "pro", store.ai_plan
    assert_equal 250, store.ai_request_limit
    assert_equal "2/250", store.ai_usage_summary
    assert store.consume_ai_request!
    assert_equal 3, store.reload.ai_requests_count
  end

  test "resets the monthly counter when the period changes" do
    store = @user.stores.create!(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      ai_requests_count: 25,
      ai_requests_counted_on: 1.month.ago.to_date
    )

    assert_equal "0/25", store.ai_usage_summary
    assert store.consume_ai_request!
    assert_equal 1, store.reload.ai_requests_count
    assert_equal Time.current.beginning_of_month.to_date, store.ai_requests_counted_on
  end

  test "mark uninstalled deactivates store and clears access token" do
    store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    uninstalled_at = Time.zone.local(2026, 6, 24, 9, 15)

    store.mark_uninstalled!(at: uninstalled_at)

    assert_not store.reload.active?
    assert_nil store.access_token
    assert_equal uninstalled_at, store.uninstalled_at
  end

  test "allows valid shop metadata" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      name: "North Pine",
      owner_email: "owner@north-pine.example",
      currency: "EUR",
      shopify_plan: "Basic"
    )

    assert_predicate store, :valid?
  end

  test "requires a valid owner email when present" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      owner_email: "not-an-email"
    )

    assert_not store.valid?
    assert_includes store.errors[:owner_email], "is invalid"
  end

  test "requires a three-letter currency when present" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      currency: "EURO"
    )

    assert_not store.valid?
    assert_includes store.errors[:currency], "is the wrong length (should be 3 characters)"
  end

  test "requires a non-negative product count" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      products_count: -1
    )

    assert_not store.valid?
    assert_includes store.errors[:products_count], "must be greater than or equal to 0"
  end

  test "requires non-negative order statistics" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      orders_count: -1,
      orders_total_price: -1
    )

    assert_not store.valid?
    assert_includes store.errors[:orders_count], "must be greater than or equal to 0"
    assert_includes store.errors[:orders_total_price], "must be greater than or equal to 0"
  end

  test "requires a three-letter order currency when present" do
    store = @user.stores.build(
      shopify_domain: "north-pine.myshopify.com",
      access_token: "shpat_secret",
      orders_currency: "EURO"
    )

    assert_not store.valid?
    assert_includes store.errors[:orders_currency], "is the wrong length (should be 3 characters)"
  end

  test "encrypts the access token at rest" do
    token = "shpat_do_not_store_in_plaintext"
    store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: token)

    stored_value = Store.connection.select_value(
      Store.sanitize_sql_array([ "SELECT access_token FROM stores WHERE id = ?", store.id ])
    )

    refute_equal token, stored_value
    assert_equal token, store.reload.access_token
  end
end
