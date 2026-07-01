module Audits
  class ProductQualityRule
    KEY = "product_quality"
    CATEGORY = "product_quality"
    SHORT_DESCRIPTION_LENGTH = 80
    WEAK_TITLE_LENGTH = 8
    GENERIC_TITLES = [
      "product",
      "untitled",
      "new product",
      "sample product"
    ].freeze

    def key
      KEY
    end

    def call(store:, audit_run:)
      snapshots = latest_snapshots(store)
      return if snapshots.empty?

      issue_groups = {
        missing_descriptions: snapshots.select { |snapshot| snapshot.description.blank? },
        short_descriptions: snapshots.select { |snapshot| short_description?(snapshot) },
        missing_images: snapshots.select { |snapshot| snapshot.image_count.zero? },
        weak_titles: snapshots.select { |snapshot| weak_title?(snapshot) }
      }
      issue_count = issue_groups.values.sum(&:size)
      return if issue_count.zero?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Product catalog quality issues found",
        severity: severity_for(issue_count, snapshots.size),
        category: CATEGORY,
        description: description_for(issue_count, snapshots.size),
        recommendation: recommendation_for(issue_groups),
        details: details_for(issue_groups, issue_count)
      )
    end

    private

    def latest_snapshots(store)
      store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def short_description?(snapshot)
      snapshot.description.present? && plain_text(snapshot.description).length < SHORT_DESCRIPTION_LENGTH
    end

    def weak_title?(snapshot)
      title = snapshot.title.to_s.strip

      title.blank? || title.length < WEAK_TITLE_LENGTH || GENERIC_TITLES.include?(title.downcase)
    end

    def plain_text(value)
      ActionView::Base.full_sanitizer.sanitize(value.to_s).squish
    end

    def severity_for(issue_count, product_count)
      issue_ratio = issue_count.to_f / product_count

      if issue_ratio >= 0.5
        "high"
      elsif issue_ratio >= 0.2
        "medium"
      else
        "low"
      end
    end

    def description_for(issue_count, product_count)
      "#{issue_count} product quality issue#{'s' unless issue_count == 1} found across #{product_count} synced product#{'s' unless product_count == 1}."
    end

    def recommendation_for(issue_groups)
      recommendations = []
      recommendations << "Add clear product descriptions." if issue_groups.fetch(:missing_descriptions).any?
      recommendations << "Expand short descriptions with benefits, materials, sizing or use cases." if issue_groups.fetch(:short_descriptions).any?
      recommendations << "Add at least one product image." if issue_groups.fetch(:missing_images).any?
      recommendations << "Rewrite missing or generic product titles so merchants and shoppers can identify the item quickly." if issue_groups.fetch(:weak_titles).any?

      recommendations.join(" ")
    end

    def details_for(issue_groups, issue_count)
      {
        issue_count:,
        missing_description_count: issue_groups.fetch(:missing_descriptions).size,
        short_description_count: issue_groups.fetch(:short_descriptions).size,
        missing_image_count: issue_groups.fetch(:missing_images).size,
        weak_title_count: issue_groups.fetch(:weak_titles).size,
        affected_product_ids: issue_groups.values.flatten.uniq.map(&:shopify_product_id)
      }
    end
  end
end
