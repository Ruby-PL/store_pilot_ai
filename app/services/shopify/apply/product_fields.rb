# frozen_string_literal: true

module Shopify
  module Apply
    # Applies StorePilot-drafted product fields (SEO title/description, catalog
    # title/description) to Shopify via a single productUpdate per product.
    # Returns one Outcome per product; never raises for a single product's
    # failure — the error is captured on that product's Outcome.
    class ProductFields
      Outcome = Data.define(:product_id, :applied, :errors)

      MUTATION = <<~GRAPHQL
        mutation ApplyProductFields($product: ProductUpdateInput!) {
          productUpdate(product: $product) {
            product { id title descriptionHtml seo { title description } }
            userErrors { field message }
          }
        }
      GRAPHQL

      # Maps a change hash key to the ProductUpdateInput shape.
      INPUT_BUILDERS = {
        "seo_title"        => ->(input, value) { (input[:seo] ||= {})[:title] = value },
        "seo_description"  => ->(input, value) { (input[:seo] ||= {})[:description] = value },
        "title"            => ->(input, value) { input[:title] = value },
        "description_html" => ->(input, value) { input[:descriptionHtml] = value }
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(store, changes, client: nil)
        @store = store
        @changes = Array(changes)
        @client = client
      end

      def call
        changes.map { |change| apply_one(change) }
      end

      private

      attr_reader :store, :changes

      def client
        @client ||= Shopify::Admin::GraphqlClient.new(shop: store.shopify_domain, access_token: store.access_token)
      end

      def apply_one(change)
        product_id = change["product_id"].to_s
        input = build_input(product_id, change)
        return Outcome.new(product_id:, applied: {}, errors: [ "No fields to apply" ]) if input.keys == [ :id ]

        data = client.query(MUTATION, variables: { product: input })
        user_errors = Array(data.dig("productUpdate", "userErrors")).map { |error| error["message"] }.compact_blank

        if user_errors.any?
          Outcome.new(product_id:, applied: {}, errors: user_errors)
        else
          Outcome.new(product_id:, applied: applied_fields(change), errors: [])
        end
      rescue Shopify::Admin::GraphqlClient::Error => error
        Outcome.new(product_id: change["product_id"].to_s, applied: {}, errors: [ error.message ])
      end

      def build_input(product_id, change)
        input = { id: product_id }
        INPUT_BUILDERS.each do |key, builder|
          value = change[key].to_s.strip
          builder.call(input, value) if value.present?
        end
        input
      end

      def applied_fields(change)
        change.slice(*INPUT_BUILDERS.keys).reject { |_, value| value.to_s.strip.blank? }
      end
    end
  end
end
