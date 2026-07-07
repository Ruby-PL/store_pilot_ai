class AuditJob < ApplicationJob
  queue_as :default

  DEFAULT_RULES = [
    Audits::ProductQualityRule,
    Audits::SeoGapRule,
    Audits::BundleOpportunityRule,
    Audits::UnderperformingProductRule,
    Audits::TopCustomerSilenceRule
  ].freeze

  def perform(store)
    AuditRunner.call(store, rules: DEFAULT_RULES.map(&:new))
  rescue StandardError => exception
    ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "audit_job" })
    Rails.logger.error("Audit job failed for store_id=#{store.id}: #{exception.message}")
  end
end
