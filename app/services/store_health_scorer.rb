class StoreHealthScorer
  CATEGORIES = %w[seo inventory product_quality revenue].freeze
  CATEGORY_BASE_SCORE = 100

  PENALTIES = {
    "high" => 25,
    "medium" => 15,
    "low" => 7
  }.freeze

  def self.call(...)
    new(...).call
  end

  def initialize(audit_run)
    @audit_run = audit_run
  end

  def call
    scores = CATEGORIES.index_with { |category| category_score(category) }
    overall = (scores.values.sum.to_f / scores.size).round
    previous = previous_completed_run

    audit_run.update!(
      overall_score: overall,
      category_scores: scores,
      previous_score_delta: previous&.overall_score ? overall - previous.overall_score : nil
    )
  end

  private

  attr_reader :audit_run

  def category_score(category)
    results = audit_run.audit_results.select { |result| result.category == category }
    penalty = results.sum { |result| PENALTIES.fetch(result.priority || "low", 0) }

    [ CATEGORY_BASE_SCORE - penalty, 0 ].max
  end

  def previous_completed_run
    audit_run.store.audit_runs
      .where.not(id: audit_run.id)
      .where.not(overall_score: nil)
      .order(completed_at: :desc, created_at: :desc)
      .first
  end
end
