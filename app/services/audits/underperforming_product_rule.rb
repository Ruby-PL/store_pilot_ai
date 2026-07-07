module Audits
  class UnderperformingProductRule
    KEY = "underperforming_product"
    CATEGORY = "revenue"
    MIN_STOCKED_PRODUCTS = 2
    MIN_AVERAGE_UNITS_SOLD = 2
    UNDERPERFORMANCE_RATIO = 0.5

    def key
      KEY
    end

    def call(store:, audit_run:)
      products = stocked_products(store)
      return if products.size < MIN_STOCKED_PRODUCTS

      sales_by_product = units_sold_by_product(store)
      average_units_sold = average_units_sold(products, sales_by_product)
      return if average_units_sold < MIN_AVERAGE_UNITS_SOLD

      underperformers = underperforming_products(products, sales_by_product, average_units_sold)
      return if underperformers.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Underperforming stocked products found",
        severity: severity_for(underperformers),
        category: CATEGORY,
        description: description_for(underperformers, average_units_sold),
        recommendation: recommendation_for(underperformers),
        details: details_for(underperformers, average_units_sold)
      )
    end

    private

    def stocked_products(store)
      latest_snapshots(store).select { |snapshot| snapshot.inventory_quantity.positive? }
    end

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def units_sold_by_product(store)
      store.order_line_item_snapshots.group(:shopify_product_id).sum(:quantity)
    end

    def average_units_sold(products, sales_by_product)
      total_units = products.sum { |product| sales_by_product.fetch(product.shopify_product_id, 0) }
      total_units.fdiv(products.size)
    end

    def underperforming_products(products, sales_by_product, average_units_sold)
      threshold = average_units_sold * UNDERPERFORMANCE_RATIO

      products.filter_map do |product|
        units_sold = sales_by_product.fetch(product.shopify_product_id, 0)
        next if units_sold > threshold

        {
          shopify_product_id: product.shopify_product_id,
          title: product.title,
          inventory_quantity: product.inventory_quantity,
          units_sold:,
          catalog_average_units_sold: average_units_sold.round(2),
          underperformance_ratio: ratio_for(units_sold, average_units_sold),
          estimated_tied_up_value: (product.price * product.inventory_quantity).round(2).to_s
        }
      end.sort_by { |product| [ product.fetch(:units_sold), -product.fetch(:inventory_quantity) ] }
    end

    def ratio_for(units_sold, average_units_sold)
      return 0 if average_units_sold.zero?

      (units_sold / average_units_sold).round(2)
    end

    def severity_for(underperformers)
      tied_up_value = underperformers.sum { |product| BigDecimal(product.fetch(:estimated_tied_up_value)) }
      return "high" if tied_up_value >= 500 || underperformers.size >= 5
      return "medium" if tied_up_value >= 100 || underperformers.size >= 3

      "low"
    end

    def description_for(underperformers, average_units_sold)
      "#{underperformers.size} stocked product#{'s' unless underperformers.size == 1} sold less than half of the catalog average of #{average_units_sold.round(2)} units."
    end

    def recommendation_for(underperformers)
      if underperformers.any? { |product| product.fetch(:units_sold).zero? }
        "Test a discount or bundle placement for products with inventory but no sales, and improve product content before increasing promotion."
      else
        "Review pricing, content quality and bundle placement for products selling below the catalog average."
      end
    end

    def details_for(underperformers, average_units_sold)
      {
        issue_count: underperformers.size,
        catalog_average_units_sold: average_units_sold.round(2),
        underperformance_ratio_threshold: UNDERPERFORMANCE_RATIO,
        estimated_tied_up_value: underperformers.sum { |product| BigDecimal(product.fetch(:estimated_tied_up_value)) }.round(2).to_s,
        affected_product_ids: underperformers.map { |product| product.fetch(:shopify_product_id) },
        underperforming_products: underperformers
      }
    end
  end
end
