require "test_helper"

class AuditRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "merchant@example.com")
    @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "belongs to a store" do
    audit_run = AuditRun.new(started_at: Time.current)

    assert_not audit_run.valid?
    assert_includes audit_run.errors[:store], "must exist"
  end

  test "requires valid status" do
    audit_run = @store.audit_runs.build(started_at: Time.current, status: "unknown")

    assert_not audit_run.valid?
    assert_includes audit_run.errors[:status], "is not included in the list"
  end

  test "complete marks completed run" do
    audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 1)

    audit_run.complete!(failed_rules: 0)

    assert_equal "completed", audit_run.status
    assert_equal 0, audit_run.failed_rule_count
    assert_predicate audit_run.completed_at, :present?
  end

  test "complete marks runs with rule failures" do
    audit_run = @store.audit_runs.create!(started_at: Time.current, rule_count: 2)

    audit_run.complete!(failed_rules: 1)

    assert_equal "completed_with_failures", audit_run.status
    assert_equal 1, audit_run.failed_rule_count
  end

  test "destroying store destroys audit runs" do
    audit_run = @store.audit_runs.create!(started_at: Time.current)

    @store.destroy!

    assert_not AuditRun.exists?(audit_run.id)
  end

  test "overall score must be between 0 and 100 when present" do
    audit_run = @store.audit_runs.build(started_at: Time.current, overall_score: 101)

    assert_not audit_run.valid?
    assert_includes audit_run.errors[:overall_score], "must be less than or equal to 100"
  end
end
