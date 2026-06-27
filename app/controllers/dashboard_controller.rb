class DashboardController < ApplicationController
  def show
    @store = current_store
    @last_sync_at = latest_sync_at(@store)
    @metrics = dashboard_metrics(@store)
  end

  def sync
    @store = current_store

    return redirect_to dashboard_path(shop: params[:shop]), alert: "Connect Shopify first." if @store.blank? || !@store.active?

    Shopify::ProductSyncJob.perform_later(@store)
    Shopify::OrderSyncJob.perform_later(@store)

    redirect_to dashboard_path(shop: @store.shopify_domain), notice: "Sync queued for #{@store.shopify_domain}."
  end

  private

  def current_store
    shop = Shopify::Oauth::Shop.sanitize(params[:shop])

    return Store.find_by(shopify_domain: shop) if shop.present?

    Store.order(updated_at: :desc).first
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
end
