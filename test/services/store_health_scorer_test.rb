require "test_helper"

class StoreHealthScorerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "merchant@example.com")
    @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "stores category scores and overall score from audit result priorities" do
    audit_run = create_audit_run!
    create_result!(audit_run, category: "seo", priority: "high")
    create_result!(audit_run, category: "inventory", priority: "medium")
    create_result!(audit_run, category: "product_quality", priority: "low")

    StoreHealthScorer.call(audit_run)

    assert_equal 88, audit_run.reload.overall_score
    assert_equal({
      "seo" => 75,
      "inventory" => 85,
      "product_quality" => 93,
      "revenue" => 100
    }, audit_run.category_scores)
  end

  test "stores delta compared with previous scored audit run" do
    create_audit_run!(completed_at: 2.days.ago, overall_score: 80)
    current = create_audit_run!(completed_at: Time.current)
    create_result!(current, category: "seo", priority: "low")

    StoreHealthScorer.call(current)

    assert_equal 98, current.reload.overall_score
    assert_equal 18, current.previous_score_delta
  end

  test "audit runner stores health score after completing a run" do
    rule = Struct.new(:key) do
      def call(store:, audit_run:)
        {
          title: "SEO issue",
          status: "warning",
          severity: "high",
          category: "seo",
          details: { issue_count: 1 }
        }
      end
    end

    audit_run = AuditRunner.call(@store, rules: [ rule.new("seo_gap") ])

    assert_equal "completed", audit_run.status
    assert_equal 94, audit_run.reload.overall_score
    assert_equal 75, audit_run.category_scores.fetch("seo")
  end

  private

  def create_audit_run!(attributes = {})
    @store.audit_runs.create!({
      started_at: Time.current,
      completed_at: Time.current,
      status: "completed"
    }.merge(attributes))
  end

  def create_result!(audit_run, attributes = {})
    audit_run.audit_results.create!({
      rule_key: "test_rule",
      title: "Test finding",
      status: "warning",
      severity: attributes.fetch(:priority, "low"),
      impact: "low",
      opportunity_score: 1
    }.merge(attributes))
  end
end
