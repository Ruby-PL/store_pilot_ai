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
        assert_equal 3, result.snapshots_created
      end

      assert_equal 3, @store.reload.products_count
      assert_predicate @store.products_synced_at, :present?
    end

    test "creates product snapshots from synced Shopify products" do
      with_graphql_responses(
        product_page([
          {
            "id" => "gid://shopify/Product/123",
            "title" => "Everyday Tote",
            "description" => "A practical canvas tote for daily errands.",
            "status" => "ACTIVE",
            "totalInventory" => 8,
            "images" => { "nodes" => [ { "id" => "gid://shopify/MediaImage/1" } ] },
            "variants" => { "nodes" => [ { "price" => "24.50" } ] }
          }
        ])
      ) do
        Shopify::ProductSync.call(@store)
      end

      snapshot = @store.product_snapshots.sole

      assert_equal "gid://shopify/Product/123", snapshot.shopify_product_id
      assert_equal "Everyday Tote", snapshot.title
      assert_equal "A practical canvas tote for daily errands.", snapshot.description
      assert_equal 1, snapshot.image_count
      assert_equal BigDecimal("24.50"), snapshot.price
      assert_equal 8, snapshot.inventory_quantity
      assert_equal "ACTIVE", snapshot.status
      assert_predicate snapshot.captured_at, :present?
    end

    test "logs sync result" do
      logs = capture_logs do
        with_graphql_responses(product_page(2)) do
          Shopify::ProductSync.call(@store)
        end
      end

      assert_includes logs, "Shopify product sync completed"
      assert_includes logs, "products_count=2"
      assert_includes logs, "snapshots_created=2"
    end

    test "skips failed product snapshots without breaking the sync" do
      logs = capture_logs do
        with_graphql_responses(
          product_page([
            { "id" => "gid://shopify/Product/valid", "title" => "Everyday Tote" },
            { "title" => "Missing ID" }
          ])
        ) do
          result = Shopify::ProductSync.call(@store)

          assert_equal 2, result.products_count
          assert_equal 1, result.snapshots_created
        end
      end

      assert_equal 1, @store.product_snapshots.count
      assert_includes logs, "Shopify product snapshot skipped"
      assert_includes logs, "snapshots_created=1"
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

    def product_page(products_or_count, has_next_page: false, end_cursor: nil)
      products =
        if products_or_count.is_a?(Integer)
          Array.new(products_or_count) do |index|
            {
              "id" => "gid://shopify/Product/#{index}",
              "title" => "Product #{index}",
              "description" => "Useful product #{index} description with enough detail for shoppers.",
              "status" => "ACTIVE",
              "totalInventory" => index,
              "images" => { "nodes" => [ { "id" => "gid://shopify/MediaImage/#{index}" } ] },
              "variants" => { "nodes" => [ { "price" => (index + 1).to_s } ] }
            }
          end
        else
          products_or_count
        end

      {
        "products" => {
          "nodes" => products,
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
