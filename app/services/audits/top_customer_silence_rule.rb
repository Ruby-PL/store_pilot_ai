module Audits
  class TopCustomerSilenceRule
    KEY = "top_customer_silence"
    CATEGORY = "revenue"
    TOP_SEGMENT_RATIO = 0.2
    MIN_CUSTOMERS = 3
    SILENCE_DAYS = 60
    HIGH_SILENCE_DAYS = 90

    def key
      KEY
    end

    def call(store:, audit_run:)
      summaries = customer_summaries(store)
      return if summaries.size < MIN_CUSTOMERS

      silent_customers = top_segment(summaries).select { |customer| customer.fetch(:days_since_last_order) >= SILENCE_DAYS }
      return if silent_customers.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "High-value customers have gone silent",
        severity: severity_for(silent_customers),
        category: CATEGORY,
        description: description_for(silent_customers),
        recommendation: "Prioritize a win-back offer for high-value customers who have not ordered recently.",
        details: details_for(silent_customers)
      )
    end

    private

    def customer_summaries(store)
      grouped_orders = store.order_snapshots.where.not(shopify_customer_id: nil).group_by(&:shopify_customer_id)

      grouped_orders.map do |customer_id, orders|
        total_value = orders.sum(&:total_price)
        last_order_at = orders.map(&:processed_at).max

        {
          shopify_customer_id: customer_id,
          order_count: orders.size,
          total_value: total_value.round(2).to_s,
          average_order_value: (total_value / orders.size).round(2).to_s,
          last_order_at: last_order_at.iso8601,
          days_since_last_order: ((Time.current.to_date - last_order_at.to_date).to_i),
          estimated_lost_revenue: (total_value / orders.size).round(2).to_s
        }
      end
    end

    def top_segment(summaries)
      limit = [ (summaries.size * TOP_SEGMENT_RATIO).ceil, 1 ].max
      summaries.sort_by { |customer| -BigDecimal(customer.fetch(:total_value)) }.first(limit)
    end

    def severity_for(silent_customers)
      return "high" if silent_customers.any? { |customer| customer.fetch(:days_since_last_order) >= HIGH_SILENCE_DAYS }

      "medium"
    end

    def description_for(silent_customers)
      "#{silent_customers.size} high-value customer#{'s' unless silent_customers.size == 1} have not ordered in at least #{SILENCE_DAYS} days."
    end

    def details_for(silent_customers)
      {
        issue_count: silent_customers.size,
        silence_days: SILENCE_DAYS,
        high_silence_days: HIGH_SILENCE_DAYS,
        estimated_lost_revenue: silent_customers.sum { |customer| BigDecimal(customer.fetch(:estimated_lost_revenue)) }.round(2).to_s,
        affected_customer_ids: silent_customers.map { |customer| customer.fetch(:shopify_customer_id) },
        customer_summaries: silent_customers
      }
    end
  end
end
