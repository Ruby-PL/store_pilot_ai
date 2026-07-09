# frozen_string_literal: true

require "test_helper"

module Shopify
  class OrderSyncTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret",
        currency: "EUR"
      )
    end

    test "stores recent order count, revenue and currency from Shopify GraphQL" do
      with_graphql_responses(order_page([ "10.25", "20.75" ], has_next_page: true, end_cursor: "cursor-1"), order_page([ "5.00" ])) do
        result = Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))

        assert_equal 3, result.orders_count
        assert_equal BigDecimal("36.0"), result.orders_total_price
        assert_equal "EUR", result.orders_currency
        assert_equal 3, result.snapshots_created
      end

      @store.reload

      assert_equal 3, @store.orders_count
      assert_equal BigDecimal("36.0"), @store.orders_total_price
      assert_equal "EUR", @store.orders_currency
      assert_predicate @store.orders_synced_at, :present?
    end

    test "creates order snapshots from synced Shopify orders" do
      processed_at = "2026-06-24T10:15:00Z"

      with_graphql_responses(
        order_page([
          order_hash(
            id: "gid://shopify/Order/123",
            amount: "42.50",
            processed_at:,
            customer_id: "gid://shopify/Customer/123"
          )
        ])
      ) do
        Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
      end

      snapshot = @store.order_snapshots.sole

      assert_equal "gid://shopify/Order/123", snapshot.shopify_order_id
      assert_equal BigDecimal("42.50"), snapshot.total_price
      assert_equal "EUR", snapshot.currency
      assert_equal "gid://shopify/Customer/123", snapshot.shopify_customer_id
      assert_equal Time.zone.parse(processed_at), snapshot.processed_at
      assert_predicate snapshot.captured_at, :present?
    end

    test "creates order line item snapshots from synced Shopify orders" do
      with_graphql_responses(
        order_page([
          order_hash(
            id: "gid://shopify/Order/line-items",
            amount: "42.50",
            customer_id: "gid://shopify/Customer/123",
            refunds: [
              refund_hash(line_item_id: "gid://shopify/LineItem/1", quantity: 1, amount: "12.50")
            ],
            line_items: [
              line_item_hash(
                id: "gid://shopify/LineItem/1",
                product_id: "gid://shopify/Product/1",
                title: "Canvas Tote",
                quantity: 2,
                price: "12.50"
              ),
              line_item_hash(
                id: "gid://shopify/LineItem/2",
                product_id: "gid://shopify/Product/2",
                title: "Travel Pouch",
                quantity: 1,
                price: "17.50"
              )
            ]
          )
        ])
      ) do
        Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
      end

      snapshot = @store.order_snapshots.sole
      line_items = snapshot.order_line_item_snapshots.order(:shopify_line_item_id)

      assert_equal 2, line_items.size
      assert_equal @store, line_items.first.store
      assert_equal "gid://shopify/Product/1", line_items.first.shopify_product_id
      assert_equal "Canvas Tote", line_items.first.product_title
      assert_equal 2, line_items.first.quantity
      assert_equal BigDecimal("12.50"), line_items.first.unit_price
      assert_equal 1, line_items.first.refunded_quantity
      assert_equal BigDecimal("12.50"), line_items.first.refunded_amount
    end

    test "queries orders from the last 30 days" do
      captured_variables = nil

      with_graphql_responses(order_page([ "10.00" ]), handler: ->(_query, variables) { captured_variables = variables }) do
        Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
      end

      assert_equal "processed_at:>=2026-05-25", captured_variables.fetch(:query)
    end

    test "logs sync result" do
      logs = capture_logs do
        with_graphql_responses(order_page([ "12.50", "7.50" ])) do
          Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
        end
      end

      assert_includes logs, "Shopify order sync completed"
      assert_includes logs, "orders_count=2"
      assert_includes logs, "orders_total_price=20.0"
      assert_includes logs, "orders_currency=EUR"
      assert_includes logs, "snapshots_created=2"
    end

    test "handles duplicate Shopify orders safely across syncs" do
      order = {
        "id" => "gid://shopify/Order/duplicate",
        "processedAt" => "2026-06-24T10:00:00Z",
        "totalPriceSet" => {
          "shopMoney" => {
            "amount" => "10.00",
            "currencyCode" => "EUR"
          }
        }
      }

      with_graphql_responses(order_page([ order ])) do
        Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
      end

      with_graphql_responses(order_page([ order ])) do
        Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))
      end

      assert_equal 2, @store.order_snapshots.where(shopify_order_id: "gid://shopify/Order/duplicate").count
    end

    test "stores zero totals when Shopify returns no recent orders" do
      with_graphql_responses(order_page([])) do
        result = Shopify::OrderSync.call(@store, since: Time.zone.local(2026, 5, 25))

        assert_equal 0, result.orders_count
        assert_equal BigDecimal("0"), result.orders_total_price
        assert_equal "EUR", result.orders_currency
      end

      @store.reload

      assert_equal 0, @store.orders_count
      assert_equal BigDecimal("0"), @store.orders_total_price
      assert_equal "EUR", @store.orders_currency
      assert_predicate @store.orders_synced_at, :present?
    end

    test "raises sync error when Shopify response is invalid" do
      with_graphql_responses({ "orders" => { "nodes" => [] } }) do
        assert_raises Shopify::OrderSync::Error do
          Shopify::OrderSync.call(@store)
        end
      end
    end

    private

    def with_graphql_responses(*responses, handler: ->(_query, _variables) { })
      original_method = Shopify::Admin::GraphqlClient.instance_method(:query)
      remaining_responses = responses.dup

      Shopify::Admin::GraphqlClient.define_method(:query) do |query, variables: {}|
        handler.call(query, variables)
        remaining_responses.shift || raise("Unexpected extra GraphQL request")
      end

      yield
    ensure
      Shopify::Admin::GraphqlClient.define_method(:query, original_method)
    end

    def order_page(orders_or_amounts, has_next_page: false, end_cursor: nil)
      orders =
        if orders_or_amounts.first.is_a?(Hash)
          orders_or_amounts
        else
          orders_or_amounts.map.with_index do |amount, index|
            order_hash(id: "gid://shopify/Order/#{index}", amount:)
          end
        end

      {
        "orders" => {
          "nodes" => orders,
          "pageInfo" => {
            "hasNextPage" => has_next_page,
            "endCursor" => end_cursor
          }
        }
      }
    end

    def order_hash(id:, amount:, processed_at: "2026-06-24T10:00:00Z", customer_id: nil, refunds: [], line_items: [])
      {
        "id" => id,
        "processedAt" => processed_at,
        "customer" => customer_id && { "id" => customer_id },
        "refunds" => refunds,
        "totalPriceSet" => {
          "shopMoney" => {
            "amount" => amount,
            "currencyCode" => "EUR"
          }
        },
        "lineItems" => {
          "nodes" => line_items
        }
      }
    end

    def refund_hash(line_item_id:, quantity:, amount:)
      {
        "refundLineItems" => {
          "nodes" => [
            {
              "quantity" => quantity,
              "lineItem" => {
                "id" => line_item_id
              },
              "subtotalSet" => {
                "shopMoney" => {
                  "amount" => amount
                }
              }
            }
          ]
        }
      }
    end

    def line_item_hash(id:, product_id:, title:, quantity:, price:)
      {
        "id" => id,
        "title" => title,
        "quantity" => quantity,
        "variant" => {
          "price" => price,
          "product" => {
            "id" => product_id,
            "title" => title
          }
        }
      }
    end

    def capture_logs
      io = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)

      yield

      io.string
    ensure
      Rails.logger = original_logger
    end
  end
end
