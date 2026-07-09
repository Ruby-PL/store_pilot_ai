require "test_helper"

class AuditJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "merchant@example.com")
    @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "runs audit runner with default rules" do
    called_store = nil
    called_rules = nil

    with_audit_runner(->(store, rules:) {
      called_store = store
      called_rules = rules
    }) do
      AuditJob.perform_now(@store)
    end

    assert_equal @store, called_store
    assert_equal(
      [
        Audits::ProductQualityRule,
        Audits::SeoGapRule,
        Audits::InventoryRiskRule,
        Audits::DeadStockRule,
        Audits::ReviewGapRule,
        Audits::BundleOpportunityRule,
        Audits::UnderperformingProductRule,
        Audits::TopCustomerSilenceRule,
        Audits::RepeatBuyerAnalysisRule,
        Audits::ReturnRateRule,
        Audits::PriceElasticityRule
      ],
      called_rules.map(&:class)
    )
  end

  test "generates ai recommendations after the audit completes" do
    audit_run = AuditRun.new(id: 123)
    called_audit_run = nil

    with_audit_runner(->(_store, rules:) { audit_run }) do
      with_ai_recommendation_generator(->(passed_audit_run) { called_audit_run = passed_audit_run }) do
        AuditJob.perform_now(@store)
      end
    end

    assert_equal audit_run, called_audit_run
  end

  test "captures errors without raising" do
    logs = capture_logs do
      with_audit_runner(->(_store, rules:) { raise "audit failed" }) do
        assert_nothing_raised { AuditJob.perform_now(@store) }
      end
    end

    assert_includes logs, "Audit job failed"
    assert_includes logs, "Captured exception for monitoring"
  end

  private

  def with_audit_runner(handler)
    original_method = AuditRunner.method(:call)
    AuditRunner.define_singleton_method(:call, &handler)

    yield
  ensure
    AuditRunner.define_singleton_method(:call, original_method)
  end

  def with_ai_recommendation_generator(handler)
    original_method = Ai::RecommendationGenerator.method(:call)
    Ai::RecommendationGenerator.define_singleton_method(:call, &handler)

    yield
  ensure
    Ai::RecommendationGenerator.define_singleton_method(:call, original_method)
  end

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
