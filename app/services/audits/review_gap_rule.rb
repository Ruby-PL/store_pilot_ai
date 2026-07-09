module Audits
  class ReviewGapRule
    KEY = "review_gap"
    CATEGORY = "conversion"
    SALES_THRESHOLD = BigDecimal("100")

    def key
      KEY
    end

    def initialize(sales_threshold: SALES_THRESHOLD, review_provider: nil)
      @sales_threshold = BigDecimal(sales_threshold.to_s)
      @review_provider = review_provider
    end

    def call(store:, audit_run:)
      candidates = latest_snapshots(store).select { |snapshot| sales_proxy(snapshot) > sales_threshold }
      return if candidates.empty?

      issue_groups = {
        missing_review_data: candidates.select { |snapshot| review_count_for(snapshot).nil? },
        missing_reviews: candidates.select { |snapshot| review_count_for(snapshot).to_i.zero? },
        low_reviews: candidates.select { |snapshot| review_count_for(snapshot).to_i.between?(1, 2) }
      }
      affected_products = issue_groups.values.flatten.uniq
      return if affected_products.empty?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Review coverage gaps found",
        severity: severity_for(issue_groups, affected_products),
        category: CATEGORY,
        description: description_for(affected_products.size),
        recommendation: recommendation_for(issue_groups),
        details: details_for(issue_groups, affected_products)
      )
    end

    private

    attr_reader :sales_threshold, :review_provider

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def review_count_for(snapshot)
      return unless review_provider&.respond_to?(:review_count_for)

      review_provider.review_count_for(snapshot)
    end

    def sales_proxy(snapshot)
      snapshot.price * snapshot.inventory_quantity
    end

    def severity_for(issue_groups, affected_products)
      return "high" if issue_groups.fetch(:missing_reviews).any? || issue_groups.fetch(:missing_review_data).size == affected_products.size
      return "medium" if affected_products.size >= 3

      "low"
    end

    def description_for(issue_count)
      "#{issue_count} product#{'s' unless issue_count == 1} with meaningful sales potential need review coverage attention."
    end

    def recommendation_for(issue_groups)
      recommendations = []
      recommendations << "Connect a reviews app integration so StorePilot can measure review coverage directly." if issue_groups.fetch(:missing_review_data).any?
      recommendations << "Collect first reviews for products with sales potential and no visible review count." if issue_groups.fetch(:missing_reviews).any?
      recommendations << "Request more reviews for products with thin social proof." if issue_groups.fetch(:low_reviews).any?

      recommendations.join(" ")
    end

    def details_for(issue_groups, affected_products)
      {
        issue_count: affected_products.size,
        sales_threshold: sales_threshold.to_s("F"),
        review_provider: review_provider ? review_provider.class.name : "placeholder",
        missing_review_data_count: issue_groups.fetch(:missing_review_data).size,
        missing_review_count: issue_groups.fetch(:missing_reviews).size,
        low_review_count: issue_groups.fetch(:low_reviews).size,
        affected_products: affected_products.map { |snapshot| product_details(snapshot) },
        affected_product_ids: affected_products.map(&:shopify_product_id)
      }
    end

    def product_details(snapshot)
      {
        shopify_product_id: snapshot.shopify_product_id,
        title: snapshot.title,
        sales_proxy: sales_proxy(snapshot).to_s("F"),
        review_count: review_count_for(snapshot)
      }
    end
  end
end
