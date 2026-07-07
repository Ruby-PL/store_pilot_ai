require "json"

module Ai
  class StoreContextBuilder
    MAX_AUDIT_RESULTS = 8
    MAX_REVENUE_OPPORTUNITIES = 5
    MAX_PRODUCTS = 8
    MAX_CONTEXT_CHARS = 12_000

    def self.call(...)
      new(...).call
    end

    def initialize(store)
      @store = store
    end

    def call
      context = {
        store: store_summary,
        latest_audit: latest_audit_summary,
        top_revenue_opportunities: top_revenue_opportunities,
        product_summary: product_summary,
        inventory_summary: inventory_summary
      }
      context[:meta] = {
        estimated_tokens: estimate_tokens(context),
        max_context_chars: MAX_CONTEXT_CHARS,
        truncated: JSON.generate(context).length > MAX_CONTEXT_CHARS
      }
      trim_context(context)
    end

    private

    attr_reader :store

    def store_summary
      {
        shopify_domain: store.shopify_domain,
        name: store.name,
        currency: store.orders_currency.presence || store.currency,
        products_count: store.products_count,
        orders_count: store.orders_count,
        orders_total_price: store.orders_total_price.to_s,
        products_synced_at: store.products_synced_at&.iso8601,
        orders_synced_at: store.orders_synced_at&.iso8601
      }
    end

    def latest_audit_summary
      audit_run = latest_audit_run
      return {} unless audit_run

      {
        id: audit_run.id,
        status: audit_run.status,
        overall_score: audit_run.overall_score,
        category_scores: audit_run.category_scores,
        started_at: audit_run.started_at.iso8601,
        completed_at: audit_run.completed_at&.iso8601,
        results: audit_results(audit_run).first(MAX_AUDIT_RESULTS)
      }
    end

    def top_revenue_opportunities
      return [] unless latest_audit_run

      audit_results(latest_audit_run)
        .select { |result| result.fetch(:category) == "revenue" }
        .first(MAX_REVENUE_OPPORTUNITIES)
    end

    def audit_results(audit_run)
      audit_run.audit_results
        .reject { |result| result.status == "passed" }
        .sort_by { |result| [ -result.opportunity_score.to_i, result.created_at ] }
        .map { |result| audit_result_summary(result) }
    end

    def audit_result_summary(result)
      {
        rule_key: result.rule_key,
        title: result.title,
        category: result.category,
        priority: result.priority,
        impact: result.impact,
        severity: result.severity,
        opportunity_score: result.opportunity_score,
        description: result.description,
        recommendation: result.ai_recommendation.presence || result.recommendation,
        details: safe_details(result.details)
      }
    end

    def safe_details(details)
      (details || {}).slice(
        "issue_count",
        "affected_product_ids",
        "affected_customer_ids",
        "estimated_tied_up_value",
        "estimated_lost_revenue",
        "confidence",
        "catalog_average_units_sold",
        "refund_ratio_threshold",
        "underperformance_ratio_threshold"
      )
    end

    def product_summary
      latest_product_snapshots.first(MAX_PRODUCTS).map do |snapshot|
        {
          shopify_product_id: snapshot.shopify_product_id,
          title: snapshot.title,
          status: snapshot.status,
          price: snapshot.price.to_s,
          inventory_quantity: snapshot.inventory_quantity,
          image_count: snapshot.image_count,
          captured_at: snapshot.captured_at.iso8601
        }
      end
    end

    def inventory_summary
      snapshots = latest_product_snapshots
      {
        product_count: snapshots.size,
        out_of_stock_count: snapshots.count { |snapshot| snapshot.inventory_quantity.zero? },
        low_stock_count: snapshots.count { |snapshot| snapshot.inventory_quantity.positive? && snapshot.inventory_quantity <= 3 },
        total_inventory_units: snapshots.sum(&:inventory_quantity)
      }
    end

    def latest_product_snapshots
      @latest_product_snapshots ||= store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def latest_audit_run
      @latest_audit_run ||= store.audit_runs.latest_first.includes(:audit_results).first
    end

    def estimate_tokens(context)
      (JSON.generate(context).length / 4.0).ceil
    end

    def trim_context(context)
      return context if JSON.generate(context).length <= MAX_CONTEXT_CHARS

      context[:product_summary] = context.fetch(:product_summary).first(3)
      context[:latest_audit][:results] = Array(context.dig(:latest_audit, :results)).first(3)
      context[:top_revenue_opportunities] = context.fetch(:top_revenue_opportunities).first(3)
      context[:meta][:estimated_tokens] = estimate_tokens(context.except(:meta))
      context[:meta][:truncated] = true
      context
    end
  end
end
