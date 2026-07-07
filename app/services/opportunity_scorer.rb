class OpportunityScorer
  CATEGORY_ALIASES = {
    "product_quality" => "product_quality",
    "seo" => "seo",
    "inventory" => "inventory",
    "revenue" => "revenue",
    "conversion" => "revenue",
    "operations" => "operations"
  }.freeze
  DEFAULT_CATEGORY = "operations"

  PRIORITY_SCORE = {
    "high" => 3,
    "medium" => 2,
    "low" => 1
  }.freeze

  IMPACT_SCORE = {
    "high" => 3,
    "medium" => 2,
    "low" => 1
  }.freeze

  Score = Data.define(:priority, :category, :impact, :opportunity_score)

  def self.call(...)
    new(...).call
  end

  def self.sort(results)
    results.sort_by do |result|
      [
        -PRIORITY_SCORE.fetch(result.priority || "low", 0),
        -IMPACT_SCORE.fetch(result.impact || "low", 0),
        -result.opportunity_score.to_i,
        result.created_at || Time.at(0)
      ]
    end
  end

  def initialize(result)
    @result = result
  end

  def call
    priority = priority_for
    impact = impact_for

    Score.new(
      priority:,
      category: category_for,
      impact:,
      opportunity_score: score_for(priority, impact)
    )
  end

  private

  attr_reader :result

  def priority_for
    case result.severity
    when "high" then "high"
    when "medium" then "medium"
    else "low"
    end
  end

  def category_for
    CATEGORY_ALIASES.fetch(result.category.to_s, DEFAULT_CATEGORY)
  end

  def impact_for
    details = result.details || {}
    issue_count = detail_value(details, :issue_count).to_i
    affected_count = Array(detail_value(details, :affected_product_ids)).size
    tied_up_value = BigDecimal(detail_value(details, :estimated_tied_up_value).presence || "0")

    return "high" if tied_up_value >= 500 || issue_count >= 10 || affected_count >= 10 || result.severity == "high"
    return "medium" if tied_up_value >= 100 || issue_count >= 3 || affected_count >= 3 || result.severity == "medium"

    "low"
  end

  def score_for(priority, impact)
    (PRIORITY_SCORE.fetch(priority) * 10) + IMPACT_SCORE.fetch(impact)
  end

  def detail_value(details, key)
    details[key.to_s] || details[key]
  end
end
