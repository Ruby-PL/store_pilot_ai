# frozen_string_literal: true

require "test_helper"

module Shopify
  class ProductSyncTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret"
      )
    end

    test "stores product count from Shopify GraphQL" do
      with_graphql_responses(product_page(2, has_next_page: true, end_cursor: "cursor-1"), product_page(1)) do
        result = Shopify::ProductSync.call(@store)

        assert_equal 3, result.products_count
      end

      assert_equal 3, @store.reload.products_count
      assert_predicate @store.products_synced_at, :present?
    end

    test "logs sync result" do
      logs = capture_logs do
        with_graphql_responses(product_page(2)) do
          Shopify::ProductSync.call(@store)
        end
      end

      assert_includes logs, "Shopify product sync completed"
      assert_includes logs, "products_count=2"
    end

    test "uses Shopify pagination cursor for additional product pages" do
      captured_variables = []

      with_graphql_responses(
        product_page(1, has_next_page: true, end_cursor: "cursor-1"),
        product_page(1),
        handler: ->(_query, variables) { captured_variables << variables }
      ) do
        Shopify::ProductSync.call(@store)
      end

      assert_equal [ { cursor: nil }, { cursor: "cursor-1" } ], captured_variables
    end

    test "raises sync error when Shopify response is invalid" do
      with_graphql_responses({ "products" => { "nodes" => [] } }) do
        assert_raises Shopify::ProductSync::Error do
          Shopify::ProductSync.call(@store)
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

    def product_page(count, has_next_page: false, end_cursor: nil)
      {
        "products" => {
          "nodes" => Array.new(count) { |index| { "id" => "gid://shopify/Product/#{index}" } },
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
