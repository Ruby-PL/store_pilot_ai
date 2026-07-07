module Audits
  class DeadStockRule
    KEY = "dead_stock"
    CATEGORY = "revenue"
    MIN_INVENTORY_QUANTITY = 3

    def key
      KEY
    end

    def call(store:, audit_run:)
      dead_stock_products = stocked_products_without_sales(store)
      return if dead_stock_products.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Dead stock found",
        severity: severity_for(dead_stock_products),
        category: CATEGORY,
        description: "#{dead_stock_products.size} stocked product#{'s' unless dead_stock_products.size == 1} have inventory but no synced sales.",
        recommendation: "Review promotion, discounting, merchandising or bundling for stocked products with no sales.",
        details: {
          issue_count: dead_stock_products.size,
          affected_product_ids: dead_stock_products.map { |product| product.fetch(:shopify_product_id) },
          estimated_tied_up_value: dead_stock_products.sum { |product| BigDecimal(product.fetch(:estimated_tied_up_value)) }.round(2).to_s,
          dead_stock_products:
        }
      )
    end

    private

    def stocked_products_without_sales(store)
      sold_product_ids = store.order_line_item_snapshots.distinct.pluck(:shopify_product_id)

      latest_snapshots(store).filter_map do |snapshot|
        next if snapshot.inventory_quantity < MIN_INVENTORY_QUANTITY
        next if sold_product_ids.include?(snapshot.shopify_product_id)

        {
          shopify_product_id: snapshot.shopify_product_id,
          title: snapshot.title,
          inventory_quantity: snapshot.inventory_quantity,
          price: snapshot.price.to_s,
          estimated_tied_up_value: (snapshot.price * snapshot.inventory_quantity).round(2).to_s
        }
      end
    end

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def severity_for(dead_stock_products)
      tied_up_value = dead_stock_products.sum { |product| BigDecimal(product.fetch(:estimated_tied_up_value)) }
      return "high" if tied_up_value >= 500 || dead_stock_products.size >= 5
      return "medium" if tied_up_value >= 100 || dead_stock_products.size >= 3

      "low"
    end
  end
end
