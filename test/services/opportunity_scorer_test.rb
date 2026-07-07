require "test_helper"

class OpportunityScorerTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    @audit_run = store.audit_runs.create!(started_at: Time.current)
  end

  test "scores high severity results as high priority opportunities" do
    result = build_result(
      severity: "high",
      category: "seo",
      details: { issue_count: 2, affected_product_ids: [ "gid://shopify/Product/1" ] }
    )

    score = OpportunityScorer.call(result)

    assert_equal "high", score.priority
    assert_equal "seo", score.category
    assert_equal "high", score.impact
    assert_equal 33, score.opportunity_score
  end

  test "normalizes unsupported categories to operations" do
    result = build_result(severity: "low", category: "unknown")

    score = OpportunityScorer.call(result)

    assert_equal "operations", score.category
    assert_equal "low", score.priority
    assert_equal "low", score.impact
  end

  test "uses tied up value and affected products to estimate impact" do
    result = build_result(
      severity: "low",
      category: "revenue",
      details: {
        "estimated_tied_up_value" => "750.00",
        "affected_product_ids" => [ "1", "2", "3" ]
      }
    )

    score = OpportunityScorer.call(result)

    assert_equal "low", score.priority
    assert_equal "high", score.impact
    assert_equal 13, score.opportunity_score
  end

  test "sorts results by priority impact and opportunity score" do
    low = create_result!(severity: "low", category: "seo")
    high = create_result!(severity: "high", category: "inventory")
    medium = create_result!(severity: "medium", category: "revenue", details: { issue_count: 3 })

    assert_equal [ high, medium, low ], OpportunityScorer.sort([ low, high, medium ])
  end

  private

  def build_result(**attributes)
    @audit_run.audit_results.build({
      rule_key: "test_rule",
      title: "Test finding",
      status: "warning"
    }.merge(attributes))
  end

  def create_result!(**attributes)
    result = build_result(**attributes)
    score = OpportunityScorer.call(result)
    result.assign_attributes(
      priority: score.priority,
      category: score.category,
      impact: score.impact,
      opportunity_score: score.opportunity_score
    )
    result.save!
    result
  end
end
