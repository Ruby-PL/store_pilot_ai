module Audits
  class BundleOpportunityRule
    KEY = "bundle_opportunity"
    CATEGORY = "revenue"
    MIN_PAIR_FREQUENCY = 3
    MIN_CONFIDENCE = 0.2

    def key
      KEY
    end

    def initialize(min_pair_frequency: MIN_PAIR_FREQUENCY, min_confidence: MIN_CONFIDENCE)
      @min_pair_frequency = min_pair_frequency
      @min_confidence = min_confidence
    end

    def call(store:, audit_run:)
      order_product_sets = product_sets_by_order(store)
      return if order_product_sets.empty?

      opportunities = bundle_pairs(order_product_sets)
      return if opportunities.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Bundle opportunities found",
        severity: severity_for(opportunities),
        category: CATEGORY,
        description: description_for(opportunities),
        recommendation: "Review the strongest co-purchased product pairs and test a bundle offer or cross-sell placement.",
        details: details_for(opportunities)
      )
    end

    private

    attr_reader :min_pair_frequency, :min_confidence

    def product_sets_by_order(store)
      store.order_line_item_snapshots
        .includes(:order_snapshot)
        .group_by(&:order_snapshot_id)
        .values
        .map { |line_items| unique_products(line_items) }
        .select { |products| products.size >= 2 }
    end

    def unique_products(line_items)
      line_items.each_with_object({}) do |line_item, products|
        products[line_item.shopify_product_id] ||= {
          shopify_product_id: line_item.shopify_product_id,
          title: line_item.product_title
        }
      end.values
    end

    def bundle_pairs(order_product_sets)
      product_order_counts = product_counts(order_product_sets)
      pair_counts = Hash.new(0)
      pair_titles = {}

      order_product_sets.each do |products|
        products.combination(2).each do |left, right|
          pair = [ left.fetch(:shopify_product_id), right.fetch(:shopify_product_id) ].sort
          pair_counts[pair] += 1
          pair_titles[pair] ||= {
            left.fetch(:shopify_product_id) => left.fetch(:title),
            right.fetch(:shopify_product_id) => right.fetch(:title)
          }
        end
      end

      pair_counts.filter_map do |pair, frequency|
        average_product_orders = pair.sum { |product_id| product_order_counts.fetch(product_id) }.fdiv(2)
        confidence = frequency / average_product_orders
        next if frequency < min_pair_frequency || confidence < min_confidence

        {
          product_ids: pair,
          product_titles: pair.map { |product_id| pair_titles.fetch(pair).fetch(product_id) },
          frequency:,
          confidence: confidence.round(2)
        }
      end.sort_by { |opportunity| [ -opportunity.fetch(:frequency), -opportunity.fetch(:confidence) ] }
    end

    def product_counts(order_product_sets)
      order_product_sets.each_with_object(Hash.new(0)) do |products, counts|
        products.each { |product| counts[product.fetch(:shopify_product_id)] += 1 }
      end
    end

    def severity_for(opportunities)
      top = opportunities.first
      return "high" if top.fetch(:frequency) >= 6
      return "medium" if top.fetch(:frequency) >= 4 || top.fetch(:confidence) >= 0.4

      "low"
    end

    def description_for(opportunities)
      "#{opportunities.size} co-purchased product pair#{'s' unless opportunities.size == 1} met the bundle confidence threshold."
    end

    def details_for(opportunities)
      {
        issue_count: opportunities.size,
        min_pair_frequency:,
        min_confidence:,
        bundle_pairs: opportunities,
        affected_product_ids: opportunities.flat_map { |opportunity| opportunity.fetch(:product_ids) }.uniq
      }
    end
  end
end
