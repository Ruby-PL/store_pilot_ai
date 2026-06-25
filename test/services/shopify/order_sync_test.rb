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
      end

      @store.reload

      assert_equal 3, @store.orders_count
      assert_equal BigDecimal("36.0"), @store.orders_total_price
      assert_equal "EUR", @store.orders_currency
      assert_predicate @store.orders_synced_at, :present?
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

    def order_page(amounts, has_next_page: false, end_cursor: nil)
      {
        "orders" => {
          "nodes" => amounts.map.with_index do |amount, index|
            {
              "id" => "gid://shopify/Order/#{index}",
              "processedAt" => "2026-06-24T10:00:00Z",
              "totalPriceSet" => {
                "shopMoney" => {
                  "amount" => amount,
                  "currencyCode" => "EUR"
                }
              }
            }
          end,
          "pageInfo" => {
            "hasNextPage" => has_next_page,
            "endCursor" => end_cursor
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
