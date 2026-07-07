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
    sign_in_as(store)

    get root_url

    assert_response :success
    assert_select "h1", "North Pine"
    assert_select ".status-pill", "Connected"
    assert_select ".metric-card", 4
    assert_stat_card "Product count", "12"
    assert_stat_card "Order count", "4"
    assert_stat_card "Revenue total", "USD 120.00"
    assert_stat_card "Average order value", "USD 30.00"
    assert_select "section[aria-label='Empty dashboard state']", 0
    assert_select "dd", "north-pine.myshopify.com"
    assert_select "dd", "Connected"
    assert_select ".sync-form .sync-button", /Run sync/
  end

  test "renders dashboard path used after OAuth redirect" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )
    sign_in_as(store)

    get dashboard_path

    assert_response :success
    assert_select "h1", "North Pine"
    assert_select ".status-pill", "Connected"
  end

  test "renders opportunity dashboard from latest audit run" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com",
      products_synced_at: 1.hour.ago
    )
    audit_run = store.audit_runs.create!(
      started_at: 30.minutes.ago,
      completed_at: 20.minutes.ago,
      status: "completed",
      overall_score: 82,
      category_scores: {
        seo: 75,
        inventory: 85,
        product_quality: 93,
        revenue: 75
      }
    )
    audit_run.audit_results.create!(
      rule_key: "seo_gap",
      title: "Product SEO gaps found",
      status: "warning",
      severity: "high",
      category: "seo",
      priority: "high",
      impact: "high",
      opportunity_score: 33,
      recommendation: "Add meta descriptions.",
      ai_recommendation: "Add unique meta descriptions to your top products.",
      details: { affected_product_ids: [ "gid://shopify/Product/1" ] }
    )
    sign_in_as(store)

    get root_url

    assert_response :success
    assert_select ".score-badge", "82/100"
    assert_select ".metric-card", text: /Opportunities found.*1/m
    assert_select ".opportunity-group h3", "High priority"
    assert_select ".opportunity-item strong", "Product SEO gaps found"
    assert_select ".opportunity-item p", "Add unique meta descriptions to your top products."
    assert_select ".opportunity-item small", /gid:\/\/shopify\/Product\/1/
  end

  test "renders opportunity empty state when no audit exists" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    sign_in_as(store)

    get root_url

    assert_response :success
    assert_select "#opportunities h3", "No audit yet"
  end

  test "renders opportunity loading state for running audit" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    store.audit_runs.create!(started_at: Time.current, status: "running")
    sign_in_as(store)

    get root_url

    assert_response :success
    assert_select "#opportunities h3", "Audit running"
  end

  test "does not select a store from the shop query parameter without a session" do
    create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )

    get dashboard_path(shop: "north-pine.myshopify.com")

    assert_response :success
    assert_select "h1", "StorePilot AI"
    assert_select ".status-pill", "Not connected"
    assert_select "dd", "Not connected"
  end

  test "ignores shop query parameter tampering when another store is authenticated" do
    authenticated_store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )
    create_store(
      name: "South Ridge",
      shopify_domain: "south-ridge.myshopify.com"
    )
    sign_in_as(authenticated_store)

    get dashboard_path(shop: "south-ridge.myshopify.com")

    assert_response :success
    assert_select "h1", "North Pine"
    assert_select "dd", "north-pine.myshopify.com"
    assert_select "dd", { text: "south-ridge.myshopify.com", count: 0 }
  end

  test "queues product and order sync jobs from the dashboard" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )
    sign_in_as(store)

    assert_enqueued_with(job: Shopify::ProductSyncJob, args: [ store ]) do
      assert_enqueued_with(job: Shopify::OrderSyncJob, args: [ store ]) do
        post dashboard_sync_path
      end
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_select ".flash-banner.notice", /Sync queued for north-pine\.myshopify\.com\./
  end

  test "does not queue sync jobs without an authenticated store" do
    create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )

    assert_no_enqueued_jobs do
      post dashboard_sync_path(shop: "north-pine.myshopify.com")
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select ".flash-banner.alert", "Connect Shopify first."
  end

  test "does not queue sync jobs for an inactive authenticated store" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com",
      active: false,
      access_token: nil
    )
    sign_in_as(store)

    assert_no_enqueued_jobs do
      post dashboard_sync_path
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select ".status-pill", "Not connected"
    assert_select ".flash-banner.alert", "Connect Shopify first."
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

  def sign_in_as(store)
    request = ActionDispatch::Request.new(Rails.application.env_config.deep_dup)
    jar = ActionDispatch::Cookies::CookieJar.build(request, {})
    jar.signed[ApplicationController::MERCHANT_STORE_COOKIE] = store.id

    cookies[ApplicationController::MERCHANT_STORE_COOKIE] = jar[ApplicationController::MERCHANT_STORE_COOKIE]
  end
end
