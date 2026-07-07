class FirstAuditTrigger
  def self.call(...)
    new(...).call
  end

  def initialize(store)
    @store = store
  end

  def call
    return false unless ready_for_first_audit?
    return false if store.audit_runs.exists?

    AuditJob.perform_later(store)
    true
  end

  private

  attr_reader :store

  def ready_for_first_audit?
    store.products_synced_at.present? && store.orders_synced_at.present?
  end
end
