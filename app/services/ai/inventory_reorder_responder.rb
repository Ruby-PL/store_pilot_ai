module Ai
  class InventoryReorderResponder
    FALLBACK_RESPONSE = "These items look like the best reorder candidates based on recent sales and current stock. I cannot infer supplier lead times unless you provide them."
    INVENTORY_PATTERNS = [
      /what inventory to reorder/i,
      /what should i reorder/i,
      /what to reorder/i,
      /reorder priorities/i
    ].freeze
    LOW_STOCK_THRESHOLD = 3

    def self.call(...)
      new(...).call
    end

    def self.matches?(question)
      INVENTORY_PATTERNS.any? { |pattern| question.to_s.match?(pattern) }
    end

    def initialize(store:, question:, conversation: nil, provider: OpenaiProvider.new)
      @store = store
      @question = question.to_s.squish
      @conversation = conversation
      @provider = provider
    end

    def call
      conversation = current_conversation
      conversation.ai_messages.create!(role: "user", content: question)
      return blocked_conversation(conversation) unless store.consume_ai_request!

      response = provider.complete_recommendation(context: prompt_context)
      conversation.ai_messages.create!(
        role: "assistant",
        content: response.text,
        prompt_tokens: response.prompt_tokens,
        completion_tokens: response.completion_tokens,
        total_tokens: response.total_tokens
      )
      Rails.logger.info("AI inventory reorder response generated store_id=#{store.id} conversation_id=#{conversation.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
      conversation
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "ai_inventory_reorder" })
      conversation.ai_messages.create!(role: "assistant", content: fallback_response)
      conversation
    end

    private

    attr_reader :store, :question, :conversation, :provider

    def current_conversation
      @current_conversation ||= conversation || store.ai_conversations.create!(title: question.truncate(80))
    end

    def prompt_context
      {
        task: "Recommend reorder candidates using current inventory and recent sales only. Include confidence and do not guess supplier lead times.",
        question:,
        reorder_candidates: reorder_candidates,
        inventory_summary: inventory_summary
      }
    end

    def inventory_summary
      {
        product_count: latest_snapshots.size,
        low_stock_count: latest_snapshots.count { |snapshot| snapshot.inventory_quantity <= LOW_STOCK_THRESHOLD },
        out_of_stock_count: latest_snapshots.count { |snapshot| snapshot.inventory_quantity.zero? }
      }
    end

    def reorder_candidates
      latest_snapshots.filter_map do |snapshot|
        units_sold = sales_counts.fetch(snapshot.shopify_product_id, 0)
        next if units_sold.zero? && snapshot.inventory_quantity > LOW_STOCK_THRESHOLD

        confidence = reorder_confidence(snapshot.inventory_quantity, units_sold)
        next if confidence < 0.2

        {
          shopify_product_id: snapshot.shopify_product_id,
          title: snapshot.title,
          inventory_quantity: snapshot.inventory_quantity,
          units_sold:,
          confidence: confidence.round(2),
          reason: reorder_reason(snapshot.inventory_quantity, units_sold)
        }
      end.sort_by { |candidate| [ -candidate.fetch(:confidence), candidate.fetch(:inventory_quantity) ] }.first(3)
    end

    def sales_counts
      @sales_counts ||= store.order_line_item_snapshots.group(:shopify_product_id).sum(:quantity)
    end

    def latest_snapshots
      @latest_snapshots ||= store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    def reorder_confidence(inventory_quantity, units_sold)
      return 0.0 if units_sold.zero? && inventory_quantity > LOW_STOCK_THRESHOLD

      baseline = [ units_sold + inventory_quantity, 1 ].max.to_f
      ((units_sold.to_f + [ LOW_STOCK_THRESHOLD - inventory_quantity, 0 ].max) / baseline).clamp(0, 1)
    end

    def reorder_reason(inventory_quantity, units_sold)
      return "Out of stock and already selling." if inventory_quantity.zero? && units_sold.positive?
      return "Low inventory with recent demand." if inventory_quantity <= LOW_STOCK_THRESHOLD && units_sold.positive?

      "Recent demand suggests replenishing soon."
    end

    def fallback_response
      candidates = reorder_candidates
      return FALLBACK_RESPONSE if candidates.empty?

      lines = [ "Reorder candidates:" ] +
        candidates.map.with_index(1) do |candidate, index|
          "#{index}. #{candidate.fetch(:title)} (confidence #{(candidate.fetch(:confidence) * 100).round}%). #{candidate.fetch(:reason)}"
        end
      lines.join(" ")
    end

    def blocked_conversation(conversation)
      conversation.ai_messages.create!(role: "assistant", content: store.ai_usage_limit_message)
      Rails.logger.info("AI inventory reorder request blocked by usage limit store_id=#{store.id} conversation_id=#{conversation.id}")
      conversation
    end
  end
end
