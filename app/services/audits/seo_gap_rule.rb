module Audits
  class SeoGapRule
    KEY = "seo_gap"
    CATEGORY = "seo"

    def key
      KEY
    end

    def call(store:, audit_run:)
      snapshots = latest_snapshots(store)
      return if snapshots.empty?

      issue_groups = {
        missing_meta_titles: snapshots.select { |snapshot| snapshot.seo_title.blank? },
        missing_meta_descriptions: snapshots.select { |snapshot| snapshot.seo_description.blank? },
        missing_image_alt_text: snapshots.select { |snapshot| missing_image_alt_text?(snapshot) }
      }
      issue_count = issue_groups.values.sum(&:size)
      return if issue_count.zero?

      AuditRunner::Result.new(
        rule_key: KEY,
        status: "warning",
        title: "Product SEO gaps found",
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

    def missing_image_alt_text?(snapshot)
      snapshot.image_count.positive? && snapshot.image_alt_text_count < snapshot.image_count
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
      "#{issue_count} SEO gap#{'s' unless issue_count == 1} found across #{product_count} synced product#{'s' unless product_count == 1}."
    end

    def recommendation_for(issue_groups)
      recommendations = []
      recommendations << "Add unique meta titles for products missing search titles." if issue_groups.fetch(:missing_meta_titles).any?
      recommendations << "Add meta descriptions that summarize product benefits and intent." if issue_groups.fetch(:missing_meta_descriptions).any?
      recommendations << "Add descriptive image alt text for product images." if issue_groups.fetch(:missing_image_alt_text).any?

      recommendations.join(" ")
    end

    def details_for(issue_groups, issue_count)
      {
        issue_count:,
        missing_meta_title_count: issue_groups.fetch(:missing_meta_titles).size,
        missing_meta_description_count: issue_groups.fetch(:missing_meta_descriptions).size,
        missing_image_alt_text_count: issue_groups.fetch(:missing_image_alt_text).size,
        affected_product_ids: issue_groups.values.flatten.uniq.map(&:shopify_product_id)
      }
    end
  end
end
