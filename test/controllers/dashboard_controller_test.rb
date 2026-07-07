require "test_helper"
require "securerandom"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @shopify_config = Rails.application.config.x.shopify
    @previous_api_secret = @shopify_config.api_secret
    @shopify_config.api_secret = "test_client_secret"
  end

  teardown do
    @shopify_config.api_secret = @previous_api_secret
  end

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

  test "renders AI Store Manager chat interface and previous messages" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    conversation = store.ai_conversations.create!(title: "What should I fix first?")
    conversation.ai_messages.create!(role: "user", content: "What should I fix first?")
    conversation.ai_messages.create!(role: "assistant", content: "Start with high priority revenue opportunities.")
    sign_in_as(store)

    get dashboard_path

    assert_response :success
    assert_select "section[aria-label='AI Store Manager'] textarea[aria-label='Ask AI Store Manager']"
    assert_select ".ai-message.user p", "What should I fix first?"
    assert_select ".ai-message.assistant p", "Start with high priority revenue opportunities."
    assert_select ".attention-item strong", "What should I fix first?"
  end

  test "stores submitted AI chat question and assistant placeholder" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    sign_in_as(store)

    post dashboard_ai_chat_path, params: { question: "Why are sales down?" }

    assert_redirected_to dashboard_path(anchor: "ai-store-manager")
    conversation = store.ai_conversations.sole
    assert_equal "Why are sales down?", conversation.title
    assert_equal [ "user", "assistant" ], conversation.ai_messages.order(:created_at).pluck(:role)
    assert_equal "Why are sales down?", conversation.ai_messages.order(:created_at).first.content
    assert_equal Ai::StoreManagerService::FALLBACK_RESPONSE, conversation.ai_messages.order(:created_at).second.content
  end

  test "shows friendly error for blank AI chat question" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    sign_in_as(store)

    post dashboard_ai_chat_path, params: { question: " " }

    assert_redirected_to dashboard_path(anchor: "ai-store-manager")
    assert_equal "Ask a question before sending.", flash[:alert]
    assert_equal 0, store.ai_conversations.count
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

  test "renders repeat buyer trend from audit result details" do
    user = User.create!(email: "merchant@example.com")
    store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    sign_in_as(store)
    audit_run = store.audit_runs.create!(
      status: "completed",
      started_at: Time.current,
      completed_at: Time.current,
      rule_count: 1,
      overall_score: 72
    )
    audit_run.audit_results.create!(
      rule_key: "repeat_buyer_analysis",
      title: "Repeat buyer retention risk found",
      status: "warning",
      severity: "high",
      category: "revenue",
      priority: "high",
      impact: "high",
      description: "Retention risk",
      details: {
        trend: {
          repeat_buyer_ratio_delta: -0.25
        }
      }
    )

    get dashboard_path

    assert_response :success
    assert_select "small", text: "Repeat buyer trend: -25%"
  end

  test "renders dedicated revenue opportunity section" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    sign_in_as(store)
    audit_run = store.audit_runs.create!(
      status: "completed",
      started_at: Time.current,
      completed_at: Time.current,
      rule_count: 4,
      overall_score: 70
    )
    [
      [ "bundle_opportunity", "Bundle opportunities found", "Test a bundle offer.", { affected_product_ids: [ "gid://shopify/Product/A" ] } ],
      [ "dead_stock", "Dead stock found", "Discount stale inventory.", { affected_product_ids: [ "gid://shopify/Product/B" ] } ],
      [ "top_customer_silence", "High-value customers have gone silent", "Send win-back offer.", { affected_customer_ids: [ "gid://shopify/Customer/A" ] } ],
      [ "underperforming_product", "Underperforming stocked products found", "Improve content or bundle placement.", { affected_product_ids: [ "gid://shopify/Product/C" ] } ]
    ].each do |rule_key, title, recommendation, details|
      audit_run.audit_results.create!(
        rule_key:,
        title:,
        status: "warning",
        severity: "medium",
        category: "revenue",
        priority: "medium",
        impact: "medium",
        recommendation:,
        details:
      )
    end

    get dashboard_path

    assert_response :success
    assert_select "section[aria-label='Revenue opportunities'] .opportunity-item", 4
    assert_select "section[aria-label='Revenue opportunities'] strong", text: "Bundle opportunities found"
    assert_select "section[aria-label='Revenue opportunities'] strong", text: "Dead stock found"
    assert_select "section[aria-label='Revenue opportunities'] strong", text: "High-value customers have gone silent"
    assert_select "section[aria-label='Revenue opportunities'] strong", text: "Underperforming stocked products found"
    assert_select "section[aria-label='Revenue opportunities'] p", text: "Test a bundle offer."
    assert_select "section[aria-label='Revenue opportunities'] small", text: /gid:\/\/shopify\/Customer\/A/
  end

  test "generates and renders win-back email draft" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    sign_in_as(store)
    audit_run = store.audit_runs.create!(status: "completed", started_at: Time.current, completed_at: Time.current)
    result = audit_run.audit_results.create!(
      rule_key: "top_customer_silence",
      title: "High-value customers have gone silent",
      status: "warning",
      severity: "high",
      category: "revenue",
      priority: "high",
      impact: "high",
      recommendation: "Send a win-back offer.",
      details: {
        estimated_lost_revenue: "150.00",
        affected_customer_ids: [ "gid://shopify/Customer/A" ]
      }
    )

    post dashboard_win_back_email_draft_path(result)

    assert_redirected_to dashboard_path(audit_run_id: audit_run.id, anchor: "opportunities")
    assert_includes result.reload.win_back_email_draft, "{{ customer_first_name }}"

    follow_redirect!

    assert_response :success
    assert_select "textarea.email-draft[readonly]", /customer_first_name/
    assert_select "textarea.email-draft", /win_back_offer/
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

  test "lists audit history and opens older audit runs" do
    store = create_store(name: "North Pine", shopify_domain: "north-pine.myshopify.com")
    old_run = store.audit_runs.create!(
      started_at: 2.days.ago,
      completed_at: 2.days.ago,
      status: "completed",
      overall_score: 70,
      category_scores: { seo: 70, inventory: 70, product_quality: 70, revenue: 70 }
    )
    old_run.audit_results.create!(
      rule_key: "seo_gap",
      title: "Old SEO issue",
      status: "warning",
      severity: "low",
      category: "seo",
      priority: "low",
      impact: "low",
      opportunity_score: 11,
      recommendation: "Old recommendation."
    )
    latest_run = store.audit_runs.create!(
      started_at: 1.day.ago,
      completed_at: 1.day.ago,
      status: "completed",
      overall_score: 85,
      previous_score_delta: 15,
      category_scores: { seo: 85, inventory: 85, product_quality: 85, revenue: 85 }
    )
    latest_run.audit_results.create!(
      rule_key: "inventory_risk",
      title: "Latest inventory issue",
      status: "warning",
      severity: "medium",
      category: "inventory",
      priority: "medium",
      impact: "medium",
      opportunity_score: 22,
      recommendation: "Latest recommendation."
    )
    sign_in_as(store)

    get root_url

    assert_response :success
    assert_select ".latest-audit strong", "Latest audit"
    assert_select ".audit-history small", /Score trend: \+15/
    assert_select ".opportunity-item strong", "Latest inventory issue"

    get dashboard_path(audit_run_id: old_run.id)

    assert_response :success
    assert_select ".score-badge", "70/100"
    assert_select ".flash-banner.notice", /Viewing audit from/
    assert_select ".opportunity-item strong", "Old SEO issue"
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

  test "signed Shopify app launch signs in an installed store" do
    store = create_store(
      name: "North Pine",
      shopify_domain: "north-pine.myshopify.com"
    )

    get root_path(shopify_launch_query(shop: store.shopify_domain))

    assert_redirected_to dashboard_path
    assert_equal store.id, signed_store_cookie

    follow_redirect!

    assert_response :success
    assert_select "h1", "North Pine"
    assert_select ".status-pill", "Connected"
  end

  test "signed Shopify app launch starts install when store is not installed" do
    get root_path(shopify_launch_query(shop: "north-pine.myshopify.com"))

    assert_redirected_to shopify_install_path(shop: "north-pine.myshopify.com")
  end

  test "Shopify app launch rejects invalid hmac" do
    get root_path(
      shop: "north-pine.myshopify.com",
      timestamp: "1710000000",
      hmac: "invalid"
    )

    assert_response :unauthorized
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

  def shopify_launch_query(shop:)
    query = {
      "shop" => shop,
      "host" => "YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUvbm9ydGgtcGluZQ",
      "session" => "session-token",
      "timestamp" => "1710000000"
    }

    query.merge("hmac" => hmac_for(query))
  end

  def hmac_for(query)
    message = query.sort.map { |key, value| "#{key}=#{value}" }.join("&")
    OpenSSL::HMAC.hexdigest("sha256", @shopify_config.api_secret, message)
  end

  def signed_store_cookie
    request = ActionDispatch::Request.new(Rails.application.env_config.deep_dup)
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)

    jar.signed[ApplicationController::MERCHANT_STORE_COOKIE]
  end
end
