module Audits
  class DeadStockRule
    KEY = "dead_stock"
    CATEGORY = "revenue"
    STALE_DAYS = 90
    CRITICAL_DAYS = 180

    def key
      KEY
    end

    def call(store:, audit_run:)
      snapshots = latest_snapshots(store).select { |snapshot| snapshot.inventory_quantity.positive? }
      return if snapshots.empty?

      candidates = snapshots.select { |snapshot| dead_stock_candidate?(snapshot) }
      return if candidates.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Dead stock opportunities found",
        severity: severity_for(candidates),
        category: CATEGORY,
        description: description_for(candidates),
        recommendation: recommendation_for(candidates),
        details: details_for(candidates)
      )
    end

    private

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def dead_stock_candidate?(snapshot)
      snapshot.captured_at <= STALE_DAYS.days.ago
    end

    def severity_for(candidates)
      return "high" if candidates.any? { |snapshot| snapshot.captured_at <= CRITICAL_DAYS.days.ago }

      tied_up_value(candidates) >= BigDecimal("500") ? "medium" : "low"
    end

    def description_for(candidates)
      "#{candidates.size} stocked product#{'s' unless candidates.size == 1} may be tying up #{format_currency(tied_up_value(candidates))} in inventory."
    end

    def recommendation_for(candidates)
      if candidates.any? { |snapshot| snapshot.captured_at <= CRITICAL_DAYS.days.ago }
        "Prioritize a clearance discount, bundle or removal plan for products with no recent movement for 180 days or more."
      else
        "Review these products for a targeted discount, bundle placement or merchandising refresh before they become long-term dead stock."
      end
    end

    def details_for(candidates)
      {
        issue_count: candidates.size,
        no_sales_90_day_count: candidates.count { |snapshot| snapshot.captured_at <= STALE_DAYS.days.ago },
        no_sales_180_day_count: candidates.count { |snapshot| snapshot.captured_at <= CRITICAL_DAYS.days.ago },
        estimated_tied_up_value: tied_up_value(candidates).to_s("F"),
        affected_products: candidates.map { |snapshot| product_details(snapshot) },
        affected_product_ids: candidates.map(&:shopify_product_id)
      }
    end

    def product_details(snapshot)
      {
        shopify_product_id: snapshot.shopify_product_id,
        title: snapshot.title,
        inventory_quantity: snapshot.inventory_quantity,
        price: snapshot.price.to_s("F"),
        estimated_tied_up_value: stock_value(snapshot).to_s("F"),
        days_since_signal: ((Time.current - snapshot.captured_at) / 1.day).floor
      }
    end

    def tied_up_value(candidates)
      candidates.sum { |snapshot| stock_value(snapshot) }
    end

    def stock_value(snapshot)
      snapshot.price * snapshot.inventory_quantity
    end

    def format_currency(value)
      "$#{format('%.2f', value)}"
    end
  end
end
