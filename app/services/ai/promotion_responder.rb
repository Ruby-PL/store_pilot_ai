module Ai
  class PromotionResponder
    FALLBACK_RESPONSE = "Promote the strongest in-stock best sellers and products linked to bundle opportunities or underperforming results."
    PROMOTION_PATTERNS = [
      /what products to promote/i,
      /which products to promote/i,
      /which products should i promote/i,
      /what should i promote/i,
      /products to promote/i
    ].freeze
    LOW_STOCK_THRESHOLD = 3

    def self.call(...)
      new(...).call
    end

    def self.matches?(question)
      PROMOTION_PATTERNS.any? { |pattern| question.to_s.match?(pattern) }
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
      Rails.logger.info("AI promotion response generated store_id=#{store.id} conversation_id=#{conversation.id} provider=#{response.provider} model=#{response.model} total_tokens=#{response.total_tokens}")
      conversation
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { store_id: store.id, source: "ai_promotion" })
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
        task: "Recommend the top 3 products to promote using best sellers, bundle opportunities, underperforming products, and inventory constraints. Explain why each one matters.",
        question:,
        promotion_candidates: promotion_candidates,
        inventory_summary: inventory_summary
      }
    end

    def inventory_summary
      snapshots = latest_snapshots
      {
        product_count: snapshots.size,
        out_of_stock_count: snapshots.count { |snapshot| snapshot.inventory_quantity.zero? },
        low_stock_count: snapshots.count { |snapshot| snapshot.inventory_quantity.positive? && snapshot.inventory_quantity <= LOW_STOCK_THRESHOLD }
      }
    end

    def promotion_candidates
      candidates = best_sellers + bundle_candidates + underperforming_candidates
      candidates
        .uniq { |candidate| candidate.fetch(:shopify_product_id) }
        .sort_by { |candidate| [ -candidate.fetch(:score), candidate.fetch(:inventory_quantity) ] }
        .first(3)
    end

    def best_sellers
      latest_snapshots.filter_map do |snapshot|
        units_sold = sales_counts.fetch(snapshot.shopify_product_id, 0)
        next if units_sold.zero? || snapshot.inventory_quantity.zero?

        {
          shopify_product_id: snapshot.shopify_product_id,
          title: snapshot.title,
          inventory_quantity: snapshot.inventory_quantity,
          units_sold:,
          score: sales_score(snapshot.inventory_quantity, units_sold),
          reason: "Strong seller with available inventory."
        }
      end
    end

    def bundle_candidates
      latest_revenue_results
        .select { |result| result.rule_key == "bundle_opportunity" }
        .flat_map do |result|
          Array(result.details&.dig("bundle_pairs")).flat_map do |pair|
            Array(pair["product_ids"]).map do |product_id|
              snapshot = snapshot_for(product_id)
              next if snapshot.blank?
              next if snapshot.inventory_quantity.zero?

              {
                shopify_product_id: snapshot.shopify_product_id,
                title: snapshot.title,
                inventory_quantity: snapshot.inventory_quantity,
                units_sold: sales_counts.fetch(snapshot.shopify_product_id, 0),
                score: pair.fetch("frequency", 0).to_i + 20,
                reason: "Frequently bought with other products."
              }
            end
          end
        end
        .compact
    end

    def underperforming_candidates
      latest_revenue_results
        .select { |result| result.rule_key == "underperforming_product" }
        .flat_map do |result|
          Array(result.details&.dig("underperforming_products")).map do |product|
            snapshot = snapshot_for(product["shopify_product_id"])
            next if snapshot.blank?
            next if snapshot.inventory_quantity.zero?

            {
              shopify_product_id: snapshot.shopify_product_id,
              title: snapshot.title,
              inventory_quantity: snapshot.inventory_quantity,
              units_sold: product["units_sold"].to_i,
              score: 30 + (snapshot.inventory_quantity - product["units_sold"].to_i),
              reason: "Has inventory but weaker sales than the catalog average."
            }
          end
        end
        .compact
    end

    def latest_revenue_results
      @latest_revenue_results ||= store.audit_runs.latest_first.includes(:audit_results).first&.audit_results&.select { |result| result.category == "revenue" } || []
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

    def snapshot_for(product_id)
      latest_snapshots.find { |snapshot| snapshot.shopify_product_id == product_id }
    end

    def sales_score(inventory_quantity, units_sold)
      [ units_sold * 2, inventory_quantity ].sum
    end

    def fallback_response
      candidates = promotion_candidates
      return FALLBACK_RESPONSE if candidates.empty?

      lines = [ "Promote these products:" ] +
        candidates.map.with_index(1) do |candidate, index|
          "#{index}. #{candidate.fetch(:title)}. #{candidate.fetch(:reason)}"
        end
      lines.join(" ")
    end

    def blocked_conversation(conversation)
      conversation.ai_messages.create!(role: "assistant", content: store.ai_usage_limit_message)
      Rails.logger.info("AI promotion request blocked by usage limit store_id=#{store.id} conversation_id=#{conversation.id}")
      conversation
    end
  end
end
