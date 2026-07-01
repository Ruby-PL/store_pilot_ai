require "test_helper"

class AuditResultTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    @audit_run = store.audit_runs.create!(started_at: Time.current)
  end

  test "belongs to an audit run" do
    result = AuditResult.new(rule_key: "product_quality", title: "Missing descriptions")

    assert_not result.valid?
    assert_includes result.errors[:audit_run], "must exist"
  end

  test "requires rule key and title" do
    result = @audit_run.audit_results.build

    assert_not result.valid?
    assert_includes result.errors[:rule_key], "can't be blank"
    assert_includes result.errors[:title], "can't be blank"
  end

  test "requires valid status" do
    result = @audit_run.audit_results.build(rule_key: "product_quality", title: "Missing descriptions", status: "unknown")

    assert_not result.valid?
    assert_includes result.errors[:status], "is not included in the list"
  end

  test "allows supported severities" do
    result = @audit_run.audit_results.build(
      rule_key: "product_quality",
      title: "Missing descriptions",
      severity: "high",
      details: { "affected_product_ids" => [ "gid://shopify/Product/1" ] }
    )

    assert_predicate result, :valid?
  end

  test "destroying audit run destroys results" do
    result = @audit_run.audit_results.create!(rule_key: "product_quality", title: "Missing descriptions")

    @audit_run.destroy!

    assert_not AuditResult.exists?(result.id)
  end
end
