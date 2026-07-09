require "test_helper"

class AuditRunnerTest < ActiveSupport::TestCase
  PassingRule = Struct.new(:key) do
    def call(store:, audit_run:)
      {
        title: "Products need better descriptions",
        status: "warning",
        severity: "medium",
        category: "product_quality",
        description: "Some products have short descriptions.",
        recommendation: "Add more detail to the affected products.",
        details: {
          store_id: store.id,
          audit_run_id: audit_run.id,
          affected_product_ids: [ "gid://shopify/Product/1" ]
        }
      }
    end
  end

  MultiResultRule = Struct.new(:key) do
    def call(store:, audit_run:)
      [
        { title: "First finding", details: { store_id: store.id } },
        AuditRunner::Result.new(
          rule_key: "custom_result_key",
          status: "warning",
          title: "Second finding",
          severity: "low",
          category: "seo",
          description: nil,
          recommendation: nil,
          details: { audit_run_id: audit_run.id }
        )
      ]
    end
  end

  FailingRule = Struct.new(:key) do
    def call(store:, audit_run:)
      raise "boom for #{store.shopify_domain} during #{audit_run.id}"
    end
  end

  setup do
    @user = User.create!(email: "merchant@example.com")
    @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "runs multiple audit rules and persists results per store" do
    audit_run = AuditRunner.call(@store, rules: [
      PassingRule.new("product_quality"),
      MultiResultRule.new("seo_gap")
    ])

    assert_equal @store, audit_run.store
    assert_equal "completed", audit_run.status
    assert_equal 2, audit_run.rule_count
    assert_equal 0, audit_run.failed_rule_count
    assert_equal 3, audit_run.audit_results.count
    assert_equal 2, audit_run.audit_actions.count

    result = audit_run.audit_results.find_by!(rule_key: "product_quality")
    assert_equal "warning", result.status
    assert_equal "medium", result.severity
    assert_equal "product_quality", result.category
    assert_equal "medium", result.priority
    assert_equal "medium", result.impact
    assert_equal 22, result.opportunity_score
    assert_equal [ "gid://shopify/Product/1" ], result.details.fetch("affected_product_ids")
    assert_equal "Products need better descriptions", result.audit_action.title
    assert_equal "Add more detail to the affected products.", result.audit_action.next_step
  end

  test "failed audit rule does not break the full audit run" do
    logs = capture_logs do
      @audit_run = AuditRunner.call(@store, rules: [
        FailingRule.new("broken_rule"),
        PassingRule.new("product_quality")
      ])
    end

    assert_equal "completed_with_failures", @audit_run.status
    assert_equal 2, @audit_run.rule_count
    assert_equal 1, @audit_run.failed_rule_count
    assert_equal 2, @audit_run.audit_results.count

    failed_result = @audit_run.audit_results.find_by!(rule_key: "broken_rule")
    assert_equal "failed", failed_result.status
    assert_equal "Broken rule failed", failed_result.title
    assert_includes failed_result.error_message, "RuntimeError: boom"
    assert_includes logs, "Captured exception for monitoring"
  end

  test "empty rule set still creates a completed audit run" do
    audit_run = AuditRunner.call(@store, rules: [])

    assert_equal "completed", audit_run.status
    assert_equal 0, audit_run.rule_count
    assert_equal 0, audit_run.audit_results.count
  end

  private

  def capture_logs
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    yield

    io.string
  ensure
    Rails.logger = original_logger
  end
end
