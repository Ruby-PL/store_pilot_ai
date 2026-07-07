module Audits
  class RepeatBuyerAnalysisRule
    KEY = "repeat_buyer_analysis"
    CATEGORY = "revenue"
    PERIOD_DAYS = 30
    MIN_CURRENT_CUSTOMERS = 3
    FIRST_TIME_RISK_RATIO = 0.7
    REPEAT_RATIO_DROP = 0.15

    def key
      KEY
    end

    def call(store:, audit_run:)
      orders = store.order_snapshots.where.not(shopify_customer_id: nil).order(:processed_at).to_a
      return if orders.empty?

      periods = period_analysis(orders)
      current = periods.fetch(:current)
      previous = periods.fetch(:previous)
      return if current.fetch(:customer_count) < MIN_CURRENT_CUSTOMERS

      repeat_ratio_delta = current.fetch(:repeat_buyer_ratio) - previous.fetch(:repeat_buyer_ratio)
      first_time_risk = current.fetch(:first_time_buyer_ratio) >= FIRST_TIME_RISK_RATIO
      repeat_drop_risk = repeat_ratio_delta <= -REPEAT_RATIO_DROP
      return unless first_time_risk || repeat_drop_risk

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Repeat buyer retention risk found",
        severity: severity_for(current, repeat_ratio_delta),
        category: CATEGORY,
        description: description_for(current, repeat_ratio_delta),
        recommendation: "Review post-purchase retention offers and win-back campaigns before increasing acquisition spend.",
        details: details_for(current, previous, repeat_ratio_delta)
      )
    end

    private

    def period_analysis(orders)
      latest_order_date = orders.map(&:processed_at).max.to_date
      current_start = latest_order_date - PERIOD_DAYS.days + 1.day
      previous_start = current_start - PERIOD_DAYS.days

      {
        current: analyze_period(orders, current_start:, current_end: latest_order_date),
        previous: analyze_period(orders, current_start: previous_start, current_end: current_start - 1.day)
      }
    end

    def analyze_period(orders, current_start:, current_end:)
      period_orders = orders.select { |order| order.processed_at.to_date.between?(current_start, current_end) }
      customer_ids = period_orders.map(&:shopify_customer_id).uniq
      first_time_customer_ids = customer_ids.select do |customer_id|
        first_order = orders.find { |order| order.shopify_customer_id == customer_id }
        first_order.processed_at.to_date.between?(current_start, current_end)
      end
      repeat_customer_ids = customer_ids - first_time_customer_ids

      {
        start_date: current_start.iso8601,
        end_date: current_end.iso8601,
        customer_count: customer_ids.size,
        first_time_customer_count: first_time_customer_ids.size,
        repeat_customer_count: repeat_customer_ids.size,
        first_time_buyer_ratio: ratio(first_time_customer_ids.size, customer_ids.size),
        repeat_buyer_ratio: ratio(repeat_customer_ids.size, customer_ids.size)
      }
    end

    def ratio(count, total)
      return 0.0 if total.zero?

      (count.fdiv(total)).round(2)
    end

    def severity_for(current, repeat_ratio_delta)
      return "high" if current.fetch(:first_time_buyer_ratio) >= 0.85 || repeat_ratio_delta <= -0.3

      "medium"
    end

    def description_for(current, repeat_ratio_delta)
      "Current first-time buyer ratio is #{percentage(current.fetch(:first_time_buyer_ratio))}, with repeat buyer ratio changed by #{percentage(repeat_ratio_delta)} versus the previous period."
    end

    def details_for(current, previous, repeat_ratio_delta)
      {
        issue_count: 1,
        period_days: PERIOD_DAYS,
        current_period: current,
        previous_period: previous,
        trend: {
          first_time_buyer_ratio_delta: (current.fetch(:first_time_buyer_ratio) - previous.fetch(:first_time_buyer_ratio)).round(2),
          repeat_buyer_ratio_delta: repeat_ratio_delta.round(2)
        }
      }
    end

    def percentage(value)
      "#{(value * 100).round}%"
    end
  end
end
