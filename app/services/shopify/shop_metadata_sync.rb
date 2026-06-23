# frozen_string_literal: true

module Shopify
  class ShopMetadataSync
    Error = Class.new(StandardError)

    SHOP_METADATA_QUERY = <<~GRAPHQL
      query StorePilotShopMetadata {
        shop {
          name
          myshopifyDomain
          email
          contactEmail
          currencyCode
          plan {
            publicDisplayName
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
      metadata = fetch_metadata
      store.update!(metadata)
      store
    end

    private

    attr_reader :store

    def fetch_metadata
      shop = graphql_client.query(SHOP_METADATA_QUERY).fetch("shop")
      domain = Shopify::Oauth::Shop.sanitize(shop.fetch("myshopifyDomain"))

      raise Error, "Shopify metadata response included an invalid shop domain" if domain.blank?

      {
        name: shop.fetch("name"),
        shopify_domain: domain,
        owner_email: shop["email"].presence || shop.fetch("contactEmail"),
        currency: shop.fetch("currencyCode").to_s,
        shopify_plan: shop.dig("plan", "publicDisplayName").presence
      }
    rescue KeyError
      raise Error, "Shopify metadata response was missing required shop fields"
    end

    def graphql_client
      Shopify::Admin::GraphqlClient.new(shop: store.shopify_domain, access_token: store.access_token)
    end
  end
end
