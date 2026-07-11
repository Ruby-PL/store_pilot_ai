module Ai
  # Drafts concrete, ready-to-use example content for the products flagged by an
  # audit finding, so the merchant sees examples of what to fill in rather than
  # only generic advice. Each supported rule declares what an "example" means
  # (which fields to draft). One AI call per finding, with a deterministic
  # fallback when AI is unavailable or the monthly limit is reached.
  #
  # Result is stored on the audit result as:
  #   details["examples"] = { "label" => "…", "items" => [ { "title" => "…",
  #     "fields" => [ { "label" => "Meta title", "value" => "…" }, … ] } ] }
  class AuditExampleGenerator
    SAMPLE_SIZE = 4
    DESCRIPTION_LIMIT = 240
    SHORT_DESCRIPTION_LENGTH = 80
    WEAK_TITLE_LENGTH = 8
    REVIEW_SALES_THRESHOLD = 100

    FIELDS = {
      "meta_title"          => { label: "Meta title",           limit: 60,  hint: "an SEO page title" },
      "meta_description"    => { label: "Meta description",      limit: 155, hint: "an SEO meta description summarising the product" },
      "image_alt"           => { label: "Image alt text",       limit: 125, hint: "descriptive image alt text" },
      "product_title"       => { label: "Suggested title",      limit: 70,  hint: "a clear, specific product title" },
      "product_description" => { label: "Suggested description", limit: 320, hint: "a compelling 1-2 sentence product description covering benefits, materials or use cases" },
      "review_request"      => { label: "Review request",       limit: 320, hint: "a short, friendly message asking a recent customer to leave a product review" }
    }.freeze

    LABELS = {
      "seo_gap"         => "Examples you could fill in",
      "product_quality" => "Suggested product copy",
      "review_gap"      => "Review requests you could send"
    }.freeze

    def self.supported?(rule_key)
      LABELS.key?(rule_key)
    end

    def self.call(...)
      new(...).call
    end

    def initialize(result, provider: OpenaiProvider.new)
      @result = result
      @provider = provider
    end

    def call
      return unless self.class.supported?(result.rule_key)

      products = gap_products
      return if products.empty?

      store_examples(generate(products).presence || template_items(products))
    rescue StandardError => exception
      ErrorMonitoring.capture_exception(exception, context: { audit_result_id: result.id, source: "ai_audit_examples" })
      products = gap_products
      store_examples(template_items(products)) if products.any?
    end

    private

    attr_reader :result, :provider

    def store_examples(items)
      result.update!(details: result.details.merge("examples" => { "label" => LABELS.fetch(result.rule_key), "items" => items }))
    end

    def generate(products)
      return template_items(products) unless result.audit_run.store.consume_ai_request!

      response = provider.complete_recommendation(context: context_for(products))
      parse(response.text, products)
    end

    # --- product / field selection -------------------------------------------

    def gap_products
      snapshots
        .filter_map { |snapshot| gap_for(snapshot) }
        .first(SAMPLE_SIZE)
    end

    def gap_for(snapshot)
      fields = fields_for(snapshot)
      return if fields.empty?

      { snapshot:, fields: }
    end

    def fields_for(snapshot)
      case result.rule_key
      when "seo_gap"         then seo_fields(snapshot)
      when "product_quality" then product_quality_fields(snapshot)
      when "review_gap"      then review_fields(snapshot)
      else []
      end
    end

    def seo_fields(snapshot)
      fields = []
      fields << "meta_title" if snapshot.seo_title.blank?
      fields << "meta_description" if snapshot.seo_description.blank?
      fields << "image_alt" if snapshot.image_count.to_i.positive? && snapshot.image_alt_text_count.to_i < snapshot.image_count.to_i
      fields
    end

    def product_quality_fields(snapshot)
      fields = []
      fields << "product_title" if weak_title?(snapshot)
      fields << "product_description" if snapshot.description.blank? || short_description?(snapshot)
      fields
    end

    def review_fields(snapshot)
      return [] unless snapshot.price.to_d * snapshot.inventory_quantity.to_i > REVIEW_SALES_THRESHOLD

      [ "review_request" ]
    end

    def weak_title?(snapshot)
      title = snapshot.title.to_s.strip
      title.blank? || title.length < WEAK_TITLE_LENGTH
    end

    def short_description?(snapshot)
      text = plain_text(snapshot.description)
      text.present? && text.length < SHORT_DESCRIPTION_LENGTH
    end

    def plain_text(value)
      value.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end

    def snapshots
      result.audit_run.store.product_snapshots
        .order(captured_at: :desc, id: :desc)
        .to_a
        .uniq(&:shopify_product_id)
    end

    # --- AI request / parsing --------------------------------------------------

    def context_for(products)
      requested = products.flat_map { |product| product.fetch(:fields) }.uniq
      hints = requested.map { |key| "#{key} (<=#{FIELDS.dig(key, :limit)} chars): #{FIELDS.dig(key, :hint)}." }

      {
        task: "For each product, draft the requested fields so the merchant can use them directly. " \
              "#{hints.join(' ')} " \
              "Only include the fields listed under \"fields\" for each product, and respect the character limits. " \
              "Return ONLY a JSON array of objects with key \"title\" plus the requested field keys. No prose and no code fences.",
        rule_key: result.rule_key,
        products: products.map do |product|
          snapshot = product.fetch(:snapshot)
          {
            title: snapshot.title,
            description: plain_text(snapshot.description).slice(0, DESCRIPTION_LIMIT),
            price: snapshot.price.to_s,
            fields: product.fetch(:fields)
          }
        end
      }
    end

    def parse(text, products)
      json = text.to_s[/\[.*\]/m]
      return template_items(products) if json.blank?

      by_title = products.index_by { |product| product.fetch(:snapshot).title }

      items = Array(JSON.parse(json)).filter_map do |row|
        next unless row.is_a?(Hash)

        title = row["title"].to_s
        allowed = by_title[title]&.fetch(:fields)
        next if allowed.blank?

        fields = allowed.filter_map do |key|
          value = row[key].to_s.strip
          { "key" => key, "label" => FIELDS.dig(key, :label), "value" => value.slice(0, FIELDS.dig(key, :limit)) } if value.present?
        end
        { "product_id" => by_title[title]&.fetch(:snapshot)&.shopify_product_id, "title" => title, "fields" => fields } if fields.any?
      end

      items.presence || template_items(products)
    rescue JSON::ParserError
      template_items(products)
    end

    # --- deterministic fallback -----------------------------------------------

    def template_items(products)
      products.map do |product|
        snapshot = product.fetch(:snapshot)
        fields = product.fetch(:fields).map do |key|
          { "key" => key, "label" => FIELDS.dig(key, :label), "value" => template_value(key, snapshot).slice(0, FIELDS.dig(key, :limit)) }
        end
        { "product_id" => snapshot.shopify_product_id, "title" => snapshot.title, "fields" => fields }
      end
    end

    def template_value(key, snapshot)
      title = snapshot.title
      description = plain_text(snapshot.description)

      case key
      when "meta_title"          then "#{title} | Shop online"
      when "meta_description"    then description.presence || "Shop the #{title} and discover why customers love it."
      when "image_alt"           then "#{title} product photo"
      when "product_title"       then title.presence || "Describe this product clearly"
      when "product_description" then description.presence || "Meet the #{title}. Add the key benefits, materials, and who it is for so shoppers can decide with confidence."
      when "review_request"      then "Hi! Thanks for your recent #{title} purchase. Would you take a minute to leave a quick review? It really helps other shoppers."
      else ""
      end
    end
  end
end
