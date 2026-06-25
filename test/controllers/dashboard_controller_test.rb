require "test_helper"
require "securerandom"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders empty dashboard shell without a connected store" do
    get root_url

    assert_response :success
    assert_select "h1", "StorePilot AI"
    assert_select ".status-pill", "Not connected"
    assert_select ".empty-state h2", "No sync data yet"
    assert_select "dd", "Not synced yet"
  end

  test "renders store connection and sync details" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com",
      products_count: 12,
      orders_count: 4,
      orders_total_price: 120,
      orders_currency: "USD",
      products_synced_at: 2.hours.ago,
      orders_synced_at: 1.hour.ago
    )

    get root_url(shop: store.shopify_domain)

    assert_response :success
    assert_select "h1", "North Pine"
    assert_select ".status-pill", "Connected"
    assert_select ".metric-card", 4
    assert_stat_card "Product count", "12"
    assert_stat_card "Order count", "4"
    assert_stat_card "Revenue total", "USD 120.00"
    assert_stat_card "Average order value", "USD 30.00"
    assert_select ".empty-state", 0
    assert_select "dd", "north-pine.myshopify.com"
    assert_select "dd", "Connected"
  end

  private

  def assert_stat_card(label, value)
    assert_select ".metric-card", text: /#{Regexp.escape(label)}.*#{Regexp.escape(value)}/m
  end

  def create_store(attributes = {})
    user = User.create!(email: "merchant-#{SecureRandom.hex(4)}@example.com")

    Store.create!({
      user: user,
      shopify_domain: "example-store.myshopify.com",
      access_token: "token",
      active: true
    }.merge(attributes))
  end
end
