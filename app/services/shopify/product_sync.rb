# frozen_string_literal: true

module Shopify
  class ProductSync
    Error = Class.new(StandardError)
    Result = Data.define(:store, :products_count)

    PRODUCTS_QUERY = <<~GRAPHQL
      query StorePilotProducts($cursor: String) {
        products(first: 250, after: $cursor) {
          nodes {
            id
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
      count = fetch_products_count

      store.update!(products_count: count, products_synced_at: Time.current)
      Rails.logger.info("Shopify product sync completed for store_id=#{store.id} products_count=#{count}")

      Result.new(store:, products_count: count)
    rescue Shopify::Admin::GraphqlClient::Error, ActiveRecord::ActiveRecordError => error
      Rails.logger.error("Shopify product sync failed for store_id=#{store.id}: #{error.message}")
      raise Error, error.message
    end

    private

    attr_reader :store

    def fetch_products_count
      count = 0
      cursor = nil

      loop do
        products = graphql_client.query(PRODUCTS_QUERY, variables: { cursor: }).fetch("products")
        count += products.fetch("nodes").size

        page_info = products.fetch("pageInfo")
        break unless page_info.fetch("hasNextPage")

        cursor = page_info.fetch("endCursor")
      end

      count
    rescue KeyError
      raise Error, "Shopify product response was missing required product fields"
    end

    def graphql_client
      @graphql_client ||= Shopify::Admin::GraphqlClient.new(
        shop: store.shopify_domain,
        access_token: store.access_token
      )
    end
  end
end
