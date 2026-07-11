class AuditJob < ApplicationJob
  queue_as :default

  DEFAULT_RULES = [
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
  ].freeze

  def perform(store)
    audit_run = AuditRunner.call(store, rules: DEFAULT_RULES.map(&:new))
    Ai::RecommendationGenerator.call(audit_run)

    audit_run.audit_results.each do |result|
      Ai::AuditExampleGenerator.call(result) if Ai::AuditExampleGenerator.supported?(result.rule_key)
    end
  rescue StandardError => exception
    ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "audit_job" })
    Rails.logger.error("Audit job failed for store_id=#{store.id}: #{exception.message}")
  end
end
