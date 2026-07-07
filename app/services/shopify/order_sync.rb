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
            customer {
              id
            }
            refunds(first: 20) {
              nodes {
                refundLineItems(first: 50) {
                  nodes {
                    quantity
                    lineItem {
                      id
                    }
                    subtotalSet {
                      shopMoney {
                        amount
                      }
                    }
                  }
                }
              }
            }
            lineItems(first: 50) {
              nodes {
                id
                title
                quantity
                variant {
                  price
                  product {
                    id
                    title
                  }
                }
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
      snapshot = store.order_snapshots.create!(
        shopify_order_id: order.fetch("id"),
        total_price: amount,
        currency:,
        shopify_customer_id: order.dig("customer", "id"),
        processed_at: Time.zone.parse(order.fetch("processedAt")),
        captured_at:
      )
      create_line_item_snapshots(
        snapshot,
        order.fetch("lineItems", {}).fetch("nodes", []),
        refunds_by_line_item: refunds_by_line_item(order),
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

    def create_line_item_snapshots(order_snapshot, line_items, refunds_by_line_item:, captured_at:)
      line_items.each do |line_item|
        product_id = line_item.dig("variant", "product", "id")
        next if product_id.blank?

        refund = refunds_by_line_item.fetch(line_item.fetch("id"), { quantity: 0, amount: BigDecimal("0") })
        order_snapshot.order_line_item_snapshots.create!(
          store:,
          shopify_line_item_id: line_item.fetch("id"),
          shopify_product_id: product_id,
          product_title: line_item.dig("variant", "product", "title").presence || line_item.fetch("title"),
          quantity: [ line_item["quantity"].to_i, 1 ].max,
          unit_price: line_item_price(line_item),
          refunded_quantity: refund.fetch(:quantity),
          refunded_amount: refund.fetch(:amount),
          captured_at:
        )
      end
    end

    def refunds_by_line_item(order)
      order.fetch("refunds", {}).fetch("nodes", []).each_with_object({}) do |refund, refunds|
        refund.fetch("refundLineItems", {}).fetch("nodes", []).each do |refund_line_item|
          line_item_id = refund_line_item.dig("lineItem", "id")
          next if line_item_id.blank?

          refunds[line_item_id] ||= { quantity: 0, amount: BigDecimal("0") }
          refunds[line_item_id][:quantity] += refund_line_item["quantity"].to_i
          refunds[line_item_id][:amount] += BigDecimal(refund_line_item.dig("subtotalSet", "shopMoney", "amount").to_s)
        rescue ArgumentError
          next
        end
      end
    end

    def line_item_price(line_item)
      BigDecimal(line_item.dig("variant", "price").to_s)
    rescue ArgumentError
      BigDecimal("0")
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
