module Audits
  class ReturnRateRule
    KEY = "return_rate"
    CATEGORY = "revenue"
    MIN_UNITS_SOLD = 3
    HIGH_REFUND_RATIO = 0.25

    def key
      KEY
    end

    def call(store:, audit_run:)
      products = product_refund_summaries(store)
      flagged_products = products.select { |product| product.fetch(:refund_ratio) >= HIGH_REFUND_RATIO }
      return if flagged_products.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "High refund ratio products found",
        severity: severity_for(flagged_products),
        category: CATEGORY,
        description: "#{flagged_products.size} product#{'s' unless flagged_products.size == 1} have refund ratios above #{(HIGH_REFUND_RATIO * 100).to_i}%.",
        recommendation: "Review product expectations, sizing, fulfillment notes and quality signals before scaling promotion.",
        details: details_for(flagged_products)
      )
    end

    private

    def product_refund_summaries(store)
      store.order_line_item_snapshots.group_by(&:shopify_product_id).filter_map do |product_id, line_items|
        units_sold = line_items.sum(&:quantity)
        next if units_sold < MIN_UNITS_SOLD

        refunded_units = line_items.sum(&:refunded_quantity)
        next if refunded_units.zero?

        {
          shopify_product_id: product_id,
          title: line_items.first.product_title,
          units_sold:,
          refunded_units:,
          refund_ratio: (refunded_units.fdiv(units_sold)).round(2),
          refunded_amount: line_items.sum(&:refunded_amount).round(2).to_s
        }
      end
    end

    def severity_for(flagged_products)
      return "high" if flagged_products.any? { |product| product.fetch(:refund_ratio) >= 0.5 }

      "medium"
    end

    def details_for(flagged_products)
      {
        issue_count: flagged_products.size,
        min_units_sold: MIN_UNITS_SOLD,
        refund_ratio_threshold: HIGH_REFUND_RATIO,
        affected_product_ids: flagged_products.map { |product| product.fetch(:shopify_product_id) },
        refunded_amount: flagged_products.sum { |product| BigDecimal(product.fetch(:refunded_amount)) }.round(2).to_s,
        return_rate_products: flagged_products
      }
    end
  end
end
