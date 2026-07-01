# frozen_string_literal: true

module Shopify
  class ProductSync
    Error = Class.new(StandardError)
    Result = Data.define(:store, :products_count, :snapshots_created)

    PRODUCTS_QUERY = <<~GRAPHQL
      query StorePilotProducts($cursor: String) {
        products(first: 250, after: $cursor) {
          nodes {
            id
            title
            description
            status
            totalInventory
            seo {
              title
              description
            }
            images(first: 10) {
              nodes {
                id
                altText
              }
            }
            variants(first: 1) {
              nodes {
                price
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    GRAPHQL

    def self.call(store)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      result = sync_products

      store.update!(products_count: result.fetch(:products_count), products_synced_at: Time.current)
      Rails.logger.info(
        "Shopify product sync completed for store_id=#{store.id} " \
        "products_count=#{result.fetch(:products_count)} snapshots_created=#{result.fetch(:snapshots_created)}"
      )

      Result.new(store:, products_count: result.fetch(:products_count), snapshots_created: result.fetch(:snapshots_created))
    rescue Shopify::Admin::GraphqlClient::Error, ActiveRecord::ActiveRecordError => error
      Rails.logger.error("Shopify product sync failed for store_id=#{store.id}: #{error.message}")
      raise Error, error.message
    end

    private

    attr_reader :store

    def sync_products
      result = { products_count: 0, snapshots_created: 0 }
      cursor = nil
      captured_at = Time.current

      loop do
        products = graphql_client.query(PRODUCTS_QUERY, variables: { cursor: }).fetch("products")
        products.fetch("nodes").each do |product|
          result[:products_count] += 1
          result[:snapshots_created] += 1 if create_snapshot(product, captured_at:)
        end

        page_info = products.fetch("pageInfo")
        break unless page_info.fetch("hasNextPage")

        cursor = page_info.fetch("endCursor")
      end

      result
    rescue KeyError
      raise Error, "Shopify product response was missing required product fields"
    end

    def create_snapshot(product, captured_at:)
      store.product_snapshots.create!(
        shopify_product_id: product.fetch("id"),
        title: product["title"].to_s,
        description: product["description"],
        image_count: product_image_count(product),
        seo_title: product.dig("seo", "title"),
        seo_description: product.dig("seo", "description"),
        image_alt_text_count: product_image_alt_text_count(product),
        price: product_price(product),
        inventory_quantity: product["totalInventory"].to_i,
        status: product["status"],
        captured_at:
      )

      true
    rescue KeyError, ActiveRecord::ActiveRecordError => error
      Rails.logger.warn(
        "Shopify product snapshot skipped for store_id=#{store.id} " \
        "shopify_product_id=#{product['id'].presence || 'unknown'}: #{error.message}"
      )
      false
    end

    def product_price(product)
      price = product.dig("variants", "nodes")&.first&.fetch("price", nil)
      BigDecimal(price.to_s)
    rescue ArgumentError, KeyError
      BigDecimal("0")
    end

    def product_image_count(product)
      product.dig("images", "nodes").to_a.size
    end

    def product_image_alt_text_count(product)
      product.dig("images", "nodes").to_a.count { |image| image["altText"].present? }
    end

    def graphql_client
      @graphql_client ||= Shopify::Admin::GraphqlClient.new(
        shop: store.shopify_domain,
        access_token: store.access_token
      )
    end
  end
end
