class AuditRunner
  Result = Data.define(:rule_key, :status, :title, :severity, :category, :description, :recommendation, :details) do
    def self.from(value, rule_key:)
      attributes = value.respond_to?(:to_h) ? value.to_h.symbolize_keys : {}

      new(
        rule_key: attributes.fetch(:rule_key, rule_key),
        status: attributes.fetch(:status, "passed"),
        title: attributes.fetch(:title),
        severity: attributes[:severity],
        category: attributes[:category],
        description: attributes[:description],
        recommendation: attributes[:recommendation],
        details: attributes.fetch(:details, {})
      )
    end
  end

  def self.call(...)
    new(...).call
  end

  def initialize(store, rules:)
    @store = store
    @rules = rules
  end

  def call
    audit_run = store.audit_runs.create!(
      status: "running",
      started_at: Time.current,
      rule_count: rules.size
    )

    failed_rules = run_rules(audit_run)
    audit_run.complete!(failed_rules: failed_rules)
    StoreHealthScorer.call(audit_run)
    audit_run
  rescue StandardError => exception
    audit_run&.fail!(failed_rules: rules.size)
    ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, audit_run_id: audit_run&.id })
    raise
  end

  private

  attr_reader :store, :rules

  def run_rules(audit_run)
    rules.count do |rule|
      run_rule(audit_run, rule)
    end
  end

  def run_rule(audit_run, rule)
    Array.wrap(execute_rule(rule, audit_run)).compact.each do |result|
      persist_result(audit_run, Result.from(result, rule_key: rule_key(rule)))
    end

    false
  rescue StandardError => exception
    ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, audit_run_id: audit_run.id, rule_key: rule_key(rule) })
    persist_rule_failure(audit_run, rule, exception)
    true
  end

  def execute_rule(rule, audit_run)
    if rule.respond_to?(:call)
      rule.call(store: store, audit_run: audit_run)
    else
      rule.run(store: store, audit_run: audit_run)
    end
  end

  def persist_result(audit_run, result)
    audit_result = audit_run.audit_results.build(
      rule_key: result.rule_key,
      status: result.status,
      severity: result.severity,
      category: result.category,
      title: result.title,
      description: result.description,
      recommendation: result.recommendation,
      details: result.details
    )
    score = OpportunityScorer.call(audit_result)
    audit_result.assign_attributes(
      priority: score.priority,
      category: score.category,
      impact: score.impact,
      opportunity_score: score.opportunity_score
    )
    audit_result.save!
  end

  def persist_rule_failure(audit_run, rule, exception)
    audit_run.audit_results.create!(
      rule_key: rule_key(rule),
      status: "failed",
      title: "#{rule_key(rule).humanize} failed",
      error_message: "#{exception.class}: #{exception.message}",
      details: {}
    )
  end

  def rule_key(rule)
    return rule.key.to_s if rule.respond_to?(:key)

    rule.class.name.underscore
  end
end
