# frozen_string_literal: true

require "test_helper"

module Shopify
  class ShopMetadataSyncTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret"
      )
    end

    test "saves shop metadata from Shopify GraphQL" do
      with_graphql_response(shop_metadata_response) do
        Shopify::ShopMetadataSync.call(@store)
      end

      @store.reload

      assert_equal "North Pine", @store.name
      assert_equal "north-pine.myshopify.com", @store.shopify_domain
      assert_equal "owner@north-pine.example", @store.owner_email
      assert_equal "EUR", @store.currency
      assert_equal "Basic", @store.shopify_plan
    end

    test "falls back to contact email when owner email is blank" do
      response = shop_metadata_response.deep_dup
      response["shop"]["email"] = ""

      with_graphql_response(response) do
        Shopify::ShopMetadataSync.call(@store)
      end

      assert_equal "contact@north-pine.example", @store.reload.owner_email
    end

    test "raises when Shopify returns an invalid shop domain" do
      response = shop_metadata_response.deep_dup
      response["shop"]["myshopifyDomain"] = "north-pine.example.com"

      with_graphql_response(response) do
        assert_raises Shopify::ShopMetadataSync::Error do
          Shopify::ShopMetadataSync.call(@store)
        end
      end
    end

    private

    def with_graphql_response(response)
      original_method = Shopify::Admin::GraphqlClient.instance_method(:query)
      Shopify::Admin::GraphqlClient.define_method(:query) { |*| response }

      yield
    ensure
      Shopify::Admin::GraphqlClient.define_method(:query, original_method)
    end

    def shop_metadata_response
      {
        "shop" => {
          "name" => "North Pine",
          "myshopifyDomain" => "north-pine.myshopify.com",
          "email" => "owner@north-pine.example",
          "contactEmail" => "contact@north-pine.example",
          "currencyCode" => "EUR",
          "plan" => {
            "publicDisplayName" => "Basic"
          }
        }
      }
    end
  end
end
