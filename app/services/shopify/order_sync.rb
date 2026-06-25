# frozen_string_literal: true

module Shopify
  class OrderSync
    Error = Class.new(StandardError)
    Result = Data.define(:store, :orders_count, :orders_total_price, :orders_currency, :snapshots_created)

    ORDERS_QUERY = <<~GRAPHQL
      query StorePilotOrders($cursor: String, $query: String!) {
        orders(first: 250, after: $cursor, query: $query, sortKey: PROCESSED_AT) {
          nodes {
            id
            processedAt
            totalPriceSet {
              shopMoney {
                amount
                currencyCode
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

    def self.call(store, since: 30.days.ago)
      new(store, since:).call
    end

    def initialize(store, since:)
      @store = store
      @since = since
    end

    def call
      totals = fetch_order_totals

      store.update!(
        orders_count: totals.fetch(:count),
        orders_total_price: totals.fetch(:total_price),
        orders_currency: totals.fetch(:currency),
        orders_synced_at: Time.current
      )
      Rails.logger.info(
        "Shopify order sync completed for store_id=#{store.id} " \
        "orders_count=#{totals.fetch(:count)} orders_total_price=#{totals.fetch(:total_price)} " \
        "orders_currency=#{totals.fetch(:currency)} snapshots_created=#{totals.fetch(:snapshots_created)}"
      )

      Result.new(
        store:,
        orders_count: totals.fetch(:count),
        orders_total_price: totals.fetch(:total_price),
        orders_currency: totals.fetch(:currency),
        snapshots_created: totals.fetch(:snapshots_created)
      )
    rescue Shopify::Admin::GraphqlClient::Error, ActiveRecord::ActiveRecordError => error
      Rails.logger.error("Shopify order sync failed for store_id=#{store.id}: #{error.message}")
      raise Error, error.message
    end

    private

    attr_reader :store, :since

    def fetch_order_totals
      totals = { count: 0, total_price: BigDecimal("0"), currency: store.currency.presence, snapshots_created: 0 }
      cursor = nil
      captured_at = Time.current

      loop do
        orders = graphql_client.query(ORDERS_QUERY, variables: { cursor:, query: orders_query }).fetch("orders")
        orders.fetch("nodes").each do |order|
          money = order.fetch("totalPriceSet").fetch("shopMoney")
          amount = BigDecimal(money.fetch("amount").to_s)
          currency = money.fetch("currencyCode")

          totals[:count] += 1
          totals[:total_price] += amount
          totals[:currency] ||= currency
          totals[:snapshots_created] += 1 if create_snapshot(order, amount:, currency:, captured_at:)
        end

        page_info = orders.fetch("pageInfo")
        break unless page_info.fetch("hasNextPage")

        cursor = page_info.fetch("endCursor")
      end

      totals
    rescue ArgumentError, KeyError
      raise Error, "Shopify order response was missing required order fields"
    end

    def create_snapshot(order, amount:, currency:, captured_at:)
      store.order_snapshots.create!(
        shopify_order_id: order.fetch("id"),
        total_price: amount,
        currency:,
        processed_at: Time.zone.parse(order.fetch("processedAt")),
        captured_at:
      )

      true
    rescue ArgumentError, KeyError, ActiveRecord::ActiveRecordError => error
      Rails.logger.warn(
        "Shopify order snapshot skipped for store_id=#{store.id} " \
        "shopify_order_id=#{order['id'].presence || 'unknown'}: #{error.message}"
      )
      false
    end

    def orders_query
      @orders_query ||= "processed_at:>=#{since.to_date.iso8601}"
    end

    def graphql_client
      @graphql_client ||= Shopify::Admin::GraphqlClient.new(
        shop: store.shopify_domain,
        access_token: store.access_token
      )
    end
  end
end
