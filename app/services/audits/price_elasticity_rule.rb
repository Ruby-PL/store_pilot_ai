module Audits
  class PriceElasticityRule
    KEY = "price_elasticity"
    CATEGORY = "revenue"
    MIN_SNAPSHOTS = 4
    MIN_FAST_SELLOUTS = 2
    FAST_SELLOUT_DAYS = 7

    def key
      KEY
    end

    def call(store:, audit_run:)
      signals = price_signals(store)
      return if signals.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Potential underpricing signals found",
        severity: severity_for(signals),
        category: CATEGORY,
        description: "#{signals.size} product#{'s' unless signals.size == 1} repeatedly sold out within #{FAST_SELLOUT_DAYS} days of restock.",
        recommendation: "Review price, margin and demand before changing price. Do not automatically increase prices from this signal alone.",
        details: {
          issue_count: signals.size,
          fast_sellout_days: FAST_SELLOUT_DAYS,
          affected_product_ids: signals.map { |signal| signal.fetch(:shopify_product_id) },
          price_elasticity_signals: signals
        }
      )
    end

    private

    def price_signals(store)
      store.product_snapshots.group_by(&:shopify_product_id).filter_map do |product_id, snapshots|
        ordered = snapshots.sort_by(&:captured_at)
        next if ordered.size < MIN_SNAPSHOTS

        sellouts = fast_sellout_cycles(ordered)
        next if sellouts.size < MIN_FAST_SELLOUTS

        {
          shopify_product_id: product_id,
          title: ordered.last.title,
          price: ordered.last.price.to_s,
          fast_sellout_count: sellouts.size,
          confidence: confidence_for(sellouts.size),
          sellout_windows: sellouts
        }
      end
    end

    def fast_sellout_cycles(snapshots)
      restock_snapshot = nil
      sellouts = []

      snapshots.each_cons(2) do |previous, current|
        restock_snapshot = current if previous.inventory_quantity.zero? && current.inventory_quantity.positive?

        next unless restock_snapshot
        next unless current.inventory_quantity.zero?

        days_to_sellout = (current.captured_at.to_date - restock_snapshot.captured_at.to_date).to_i
        next if days_to_sellout.negative?

        if days_to_sellout <= FAST_SELLOUT_DAYS
          sellouts << {
            restocked_at: restock_snapshot.captured_at.iso8601,
            sold_out_at: current.captured_at.iso8601,
            days_to_sellout:
          }
        end
        restock_snapshot = nil
      end

      sellouts
    end

    def confidence_for(fast_sellout_count)
      return "high" if fast_sellout_count >= 3

      "medium"
    end

    def severity_for(signals)
      return "high" if signals.any? { |signal| signal.fetch(:confidence) == "high" }

      "medium"
    end
  end
end
