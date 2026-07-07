module Audits
  class InventoryRiskRule
    KEY = "inventory_risk"
    CATEGORY = "inventory"
    LOW_STOCK_THRESHOLD = 5
    FAST_SELLING_DAILY_ORDER_THRESHOLD = 1.0

    def key
      KEY
    end

    def initialize(low_stock_threshold: LOW_STOCK_THRESHOLD)
      @low_stock_threshold = low_stock_threshold
    end

    def call(store:, audit_run:)
      snapshots = latest_snapshots(store)
      return if snapshots.empty?

      issue_groups = {
        out_of_stock: snapshots.select { |snapshot| snapshot.inventory_quantity.zero? },
        low_stock: snapshots.select { |snapshot| low_stock?(snapshot) },
        fast_selling_low_stock: fast_selling_low_stock_products(store, snapshots)
      }
      affected_products = issue_groups.values.flatten.uniq
      return if affected_products.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Inventory risks found",
        severity: severity_for(issue_groups, affected_products, snapshots.size),
        category: CATEGORY,
        description: description_for(affected_products.size, snapshots.size),
        recommendation: recommendation_for(issue_groups),
        details: details_for(store, issue_groups, affected_products)
      )
    end

    private

    attr_reader :low_stock_threshold

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def low_stock?(snapshot)
      snapshot.inventory_quantity.positive? && snapshot.inventory_quantity < low_stock_threshold
    end

    def fast_selling_low_stock_products(store, snapshots)
      return [] unless fast_selling_store?(store)

      snapshots.select { |snapshot| snapshot.inventory_quantity.positive? && snapshot.inventory_quantity <= low_stock_threshold }
    end

    def fast_selling_store?(store)
      recent_orders = store.order_snapshots.where(processed_at: 30.days.ago..Time.current).count
      return false if recent_orders.zero?

      recent_orders / 30.0 >= FAST_SELLING_DAILY_ORDER_THRESHOLD
    end

    def severity_for(issue_groups, affected_products, product_count)
      return "high" if issue_groups.fetch(:out_of_stock).any? || issue_groups.fetch(:fast_selling_low_stock).any?

      affected_ratio = affected_products.size.to_f / product_count
      affected_ratio >= 0.25 ? "medium" : "low"
    end

    def description_for(issue_count, product_count)
      "#{issue_count} inventory risk#{'s' unless issue_count == 1} found across #{product_count} synced product#{'s' unless product_count == 1}."
    end

    def recommendation_for(issue_groups)
      recommendations = []
      recommendations << "Restock or hide out-of-stock products before paid traffic sends shoppers to unavailable items." if issue_groups.fetch(:out_of_stock).any?
      recommendations << "Review low-stock products and reorder inventory before they sell through." if issue_groups.fetch(:low_stock).any?
      recommendations << "Prioritize replenishment for low-stock products while recent order velocity is high." if issue_groups.fetch(:fast_selling_low_stock).any?

      recommendations.join(" ")
    end

    def details_for(store, issue_groups, affected_products)
      {
        issue_count: affected_products.size,
        low_stock_threshold:,
        recent_order_count: store.order_snapshots.where(processed_at: 30.days.ago..Time.current).count,
        out_of_stock_count: issue_groups.fetch(:out_of_stock).size,
        low_stock_count: issue_groups.fetch(:low_stock).size,
        fast_selling_low_stock_count: issue_groups.fetch(:fast_selling_low_stock).size,
        stockout_risk_level: stockout_risk_level(issue_groups),
        affected_product_ids: affected_products.map(&:shopify_product_id)
      }
    end

    def stockout_risk_level(issue_groups)
      if issue_groups.fetch(:out_of_stock).any? || issue_groups.fetch(:fast_selling_low_stock).any?
        "high"
      elsif issue_groups.fetch(:low_stock).size >= 3
        "medium"
      else
        "low"
      end
    end
  end
end
