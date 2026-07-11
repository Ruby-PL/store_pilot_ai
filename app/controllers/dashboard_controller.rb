class DashboardController < ApplicationController
  before_action :authenticate_shopify_launch!, only: :show
  helper_method :opportunity_amount

  # Maps the example field key drafted by Ai::AuditExampleGenerator to the
  # change-set key understood by Shopify::Apply::ProductFields.
  APPLY_FIELD_MAP = {
    "meta_title" => "seo_title",
    "meta_description" => "seo_description",
    "product_title" => "title",
    "product_description" => "description_html"
  }.freeze

  def show
    @store = current_store
    @dashboard_section = dashboard_section
    @last_sync_at = latest_sync_at(@store)
    @metrics = dashboard_metrics(@store)
    @ai_usage_summary = @store&.ai_usage_summary
    @ai_requests_remaining = @store&.ai_requests_remaining
    @ai_plan = @store&.ai_plan&.titleize
    @audit_runs = audit_runs(@store)
    @latest_audit_run = @audit_runs.first
    @selected_audit_run = selected_audit_run(@audit_runs)
    @opportunities = opportunity_results(@selected_audit_run)
    @revenue_opportunities = @opportunities.select { |result| result.category == "revenue" }
    @opportunities_by_priority = @opportunities.group_by(&:priority)
    @category_scores = @selected_audit_run&.category_scores || {}
    @store_product_titles = store_product_titles(@store)
    @audit_actions = audit_actions(@selected_audit_run)
    @open_audit_actions = @audit_actions.reject { |action| action.status == "completed" }
    @completed_audit_actions = completed_audit_actions(@selected_audit_run)
    @action_summary = action_summary(@selected_audit_run, @audit_actions)
    @hero_opportunity = @opportunities.first
    @priority_opportunities = @opportunities.first(3)
    @hero_amount = opportunity_amount(@hero_opportunity) || "€240"
    @activity_runs = @audit_runs.first(4)
    @ai_conversations = ai_conversations(@store)
    @ai_conversation = selected_ai_conversation(@ai_conversations)
    @ai_messages = @ai_conversation&.ai_messages&.order(:created_at) || []
    @store_overview_rows = store_overview_rows(@store)
  end

  def sync
    @store = current_store

    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    Shopify::ProductSyncJob.perform_later(@store)
    Shopify::OrderSyncJob.perform_later(@store)

    redirect_to dashboard_path, notice: "Sync queued for #{@store.shopify_domain}."
  end

  def generate_win_back_email_draft
    @store = current_store
    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    result = @store.audit_results.find(params[:id])
    Ai::WinBackEmailDraftGenerator.call(result)

    redirect_to dashboard_path(section: "opportunities", audit_run_id: result.audit_run_id, anchor: "opportunities"), notice: "Win-back email draft generated."
  end

  def apply_audit_result
    @store = current_store
    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    result = @store.audit_results.find(params[:id])
    changes = apply_changes_for(result)

    if changes.empty?
      return redirect_to dashboard_path(section: "opportunities", audit_run_id: result.audit_run_id, anchor: "opportunities"), alert: "Nothing to apply."
    end

    outcomes = Shopify::Apply::ProductFields.call(@store, changes)
    applied = outcomes.count { |outcome| outcome.errors.empty? }
    failed = outcomes.size - applied
    record_application(result, outcomes, applied)

    notice =
      if failed.zero?
        "Applied to #{applied} #{'product'.pluralize(applied)} in Shopify."
      else
        "Applied to #{applied} #{'product'.pluralize(applied)}; #{failed} failed."
      end

    redirect_to dashboard_path(section: "opportunities", audit_run_id: result.audit_run_id, anchor: "opportunities"), notice:
  end

  def create_ai_chat_message
    @store = current_store
    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    question = params[:question].to_s.squish
    return redirect_to dashboard_path(anchor: "ai-store-manager"), alert: "Ask a question before sending." if question.blank?

    conversation = selected_ai_conversation(@store.ai_conversations.latest_first) || @store.ai_conversations.create!(title: question.truncate(80))
    Ai::StoreManagerService.call(store: @store, question:, conversation:)

    redirect_to dashboard_path(ai_conversation_id: conversation.id, anchor: "ai-store-manager"), notice: "Question saved."
  end

  def complete_audit_action
    @store = current_store
    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    action = @store.audit_actions.find(params[:id])
    action.complete!(
      merchant_note: params[:merchant_note],
      reference_url: params[:reference_url]
    )

    redirect_to dashboard_path(section: "activity", audit_run_id: action.audit_run_id, anchor: "action-center"), notice: "Action marked complete."
  end

  def update_audit_action
    @store = current_store
    return redirect_to dashboard_path, alert: "Connect Shopify first." if @store.blank?

    action = @store.audit_actions.find(params[:id])
    merchant_note = params[:merchant_note].to_s.strip
    reference_url = params[:reference_url].to_s.strip

    if params[:action_status] == "completed"
      action.complete!(merchant_note:, reference_url:)
      notice = "Action marked complete."
    else
      action.update_tracking!(merchant_note:, reference_url:)
      notice = "Action updated."
    end

    redirect_to dashboard_path(section: "activity", audit_run_id: action.audit_run_id, anchor: "action-center"), notice:
  end

  private

  def authenticate_shopify_launch!
    return if cookies.signed[MERCHANT_STORE_COOKIE].present?
    return unless shopify_launch_request?
    return head :unauthorized unless Shopify::Oauth::HmacVerifier.valid?(request.query_parameters)

    shop = Shopify::Oauth::Shop.sanitize(params[:shop])
    return head :bad_request unless shop

    store = Store.find_by(shopify_domain: shop)
    if store&.active?
      sign_in_store(store)
      redirect_to dashboard_path(anchor: params[:anchor])
    else
      redirect_to shopify_install_path(shop:)
    end
  end

  def shopify_launch_request?
    params[:shop].present? && params[:hmac].present? && params[:timestamp].present?
  end

  def latest_sync_at(store)
    return if store.blank?

    [ store.products_synced_at, store.orders_synced_at ].compact.max
  end

  def dashboard_metrics(store)
    return [] if store.blank?

    currency = store.orders_currency.presence || store.currency.presence
    orders_count = store.orders_count.to_i
    revenue = BigDecimal(store.orders_total_price.to_s)

    [
      { label: "Product count", value: store.products_count.to_i.to_s },
      { label: "Order count", value: orders_count.to_s },
      { label: "Revenue total", value: format_money(revenue, currency) },
      { label: "Average order value", value: orders_count.positive? ? format_money(revenue / orders_count, currency) : "Not available" }
    ]
  end

  def format_money(amount, currency)
    return "Not available" if currency.blank?

    "#{currency} #{format('%.2f', amount)}"
  end

  def opportunity_results(audit_run)
    return [] if audit_run.blank?

    OpportunityScorer.sort(audit_run.audit_results.reject { |result| result.status == "passed" })
  end

  def audit_runs(store)
    return AuditRun.none if store.blank?

    store.audit_runs.latest_first.includes(:audit_results)
  end

  def selected_audit_run(audit_runs)
    return if audit_runs.blank?
    return audit_runs.first if params[:audit_run_id].blank?

    audit_runs.detect { |audit_run| audit_run.id == params[:audit_run_id].to_i } || audit_runs.first
  end

  def ai_conversations(store)
    return AiConversation.none if store.blank?

    store.ai_conversations.latest_first.includes(:ai_messages).limit(5)
  end

  def selected_ai_conversation(conversations)
    return if conversations.blank?

    conversations.detect { |conversation| conversation.id == params[:ai_conversation_id].to_i } || conversations.first
  end

  def store_overview_rows(store)
    return [] if store.blank?

    [
      {
        title: "What StorePilot AI does",
        body: "It turns synced Shopify data into plain-English guidance so merchants know what to fix first, what to promote, and what to reorder."
      },
      {
        title: "What it looks at",
        body: "Products, orders, inventory, audits, and conversation history for this store. It keeps customer data minimal and uses the latest sync results."
      },
      {
        title: "What it helps solve",
        body: "Sales drops, low-performing products, bundle opportunities, dead stock, reorder decisions, and recurring issues that need merchant review."
      }
    ]
  end

  def store_product_titles(store)
    return {} if store.blank?

    store.product_snapshots.order(captured_at: :desc, id: :desc).to_a.uniq(&:shopify_product_id).each_with_object({}) do |snapshot, titles|
      titles[snapshot.shopify_product_id] = snapshot.title
    end
  end

  def audit_actions(audit_run)
    return AuditAction.none if audit_run.blank?

    audit_run.audit_actions.includes(:audit_result).open_first
  end

  def completed_audit_actions(audit_run)
    return AuditAction.none if audit_run.blank?

    audit_run.audit_actions.includes(:audit_result).completed_first
  end

  def action_summary(audit_run, actions)
    return {} if audit_run.blank?

    {
      open_count: actions.count { |action| action.status == "open" },
      completed_count: actions.count { |action| action.status == "completed" },
      previous_score_delta: audit_run.previous_score_delta,
      completed_at: audit_run.completed_at
    }
  end

  def opportunity_amount(result)
    return if result.blank?

    raw_value =
      result.details["recoverable_revenue"] ||
      result.details["estimated_lost_revenue"] ||
      result.details["estimated_monthly_impact"] ||
      result.details["estimated_impact"] ||
      result.details["lost_revenue"]

    return if raw_value.blank?

    amount = BigDecimal(raw_value.to_s)
    currency = @store&.orders_currency.presence || @store&.currency.presence || "EUR"

    format_money(amount, currency)
  rescue ArgumentError
    nil
  end

  def apply_changes_for(result)
    allowed_ids = Array(result.details.dig("examples", "items")).filter_map { |item| item["product_id"] }
    rows = params[:apply].respond_to?(:values) ? params[:apply].values : []

    rows.filter_map do |row|
      product_id = row[:product_id].to_s
      next unless allowed_ids.include?(product_id)

      change = { "product_id" => product_id }
      APPLY_FIELD_MAP.each do |field_key, change_key|
        value = row[field_key].to_s.strip
        change[change_key] = value if value.present?
      end
      change if change.size > 1
    end
  end

  def record_application(result, outcomes, applied_count)
    result.update!(details: result.details.merge(
      "applied" => {
        "count" => applied_count,
        "at" => Time.current.iso8601,
        "results" => outcomes.map { |outcome| { "product_id" => outcome.product_id, "applied" => outcome.applied, "errors" => outcome.errors } }
      }
    ))
  end

  def dashboard_section
    section = params[:section].to_s
    return "today" if section.blank?
    return section if %w[today opportunities store activity].include?(section)

    "today"
  end
end
