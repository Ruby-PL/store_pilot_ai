class DashboardController < ApplicationController
  before_action :authenticate_shopify_launch!, only: :show

  def show
    @store = current_store
    @last_sync_at = latest_sync_at(@store)
    @metrics = dashboard_metrics(@store)
    @audit_runs = audit_runs(@store)
    @latest_audit_run = @audit_runs.first
    @selected_audit_run = selected_audit_run(@audit_runs)
    @opportunities = opportunity_results(@selected_audit_run)
    @opportunities_by_priority = @opportunities.group_by(&:priority)
    @category_scores = @selected_audit_run&.category_scores || {}
  end

  def sync
    @store = current_store

    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    Shopify::ProductSyncJob.perform_later(@store)
    Shopify::OrderSyncJob.perform_later(@store)

    redirect_to dashboard_path, notice: "Sync queued for #{@store.shopify_domain}."
  end

  private

  def authenticate_shopify_launch!
    return if cookies.signed[MERCHANT_STORE_COOKIE].present?
    return unless shopify_launch_request?
    return head :unauthorized unless Shopify::Oauth::HmacVerifier.valid?(request.query_parameters)

    shop = Shopify::Oauth::Shop.sanitize(params[:shop])
    return head :bad_request unless shop

    store = Store.find_by(shopify_domain: shop)
    if store&.active?
      sign_in_store(store)
      redirect_to dashboard_path(anchor: params[:anchor])
    else
      redirect_to shopify_install_path(shop:)
    end
  end

  def shopify_launch_request?
    params[:shop].present? && params[:hmac].present? && params[:timestamp].present?
  end

  def latest_sync_at(store)
    return if store.blank?

    [ store.products_synced_at, store.orders_synced_at ].compact.max
  end

  def dashboard_metrics(store)
    return [] if store.blank?

    currency = store.orders_currency.presence || store.currency.presence
    orders_count = store.orders_count.to_i
    revenue = BigDecimal(store.orders_total_price.to_s)

    [
      { label: "Product count", value: store.products_count.to_i.to_s },
      { label: "Order count", value: orders_count.to_s },
      { label: "Revenue total", value: format_money(revenue, currency) },
      { label: "Average order value", value: orders_count.positive? ? format_money(revenue / orders_count, currency) : "Not available" }
    ]
  end

  def format_money(amount, currency)
    return "Not available" if currency.blank?

    "#{currency} #{format('%.2f', amount)}"
  end

  def opportunity_results(audit_run)
    return [] if audit_run.blank?

    OpportunityScorer.sort(audit_run.audit_results.reject { |result| result.status == "passed" })
  end

  def audit_runs(store)
    return AuditRun.none if store.blank?

    store.audit_runs.latest_first.includes(:audit_results)
  end

  def selected_audit_run(audit_runs)
    return if audit_runs.blank?
    return audit_runs.first if params[:audit_run_id].blank?

    audit_runs.detect { |audit_run| audit_run.id == params[:audit_run_id].to_i } || audit_runs.first
  end
end
