# frozen_string_literal: true

require "test_helper"

module Shopify
  class WebhooksControllerTest < ActionDispatch::IntegrationTest
    setup do
      @shopify_config = Rails.application.config.x.shopify
      @previous_config = {
        api_secret: @shopify_config.api_secret,
        credentials_configured: @shopify_config.credentials_configured
      }
      @shopify_config.api_secret = "test_client_secret"
      @shopify_config.credentials_configured = true

      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    teardown do
      @previous_config.each do |name, value|
        @shopify_config.public_send("#{name}=", value)
      end
    end

    test "app uninstall webhook verifies hmac and marks store inactive" do
      post shopify_app_uninstalled_webhook_path,
        params: payload,
        headers: webhook_headers(shop: "north-pine.myshopify.com", payload:)

      assert_response :ok
      assert_not @store.reload.active?
      assert_nil @store.access_token
      assert_predicate @store.uninstalled_at, :present?
    end

    test "app uninstall webhook rejects invalid hmac" do
      post shopify_app_uninstalled_webhook_path,
        params: payload,
        headers: webhook_headers(shop: "north-pine.myshopify.com", payload:).merge("X-Shopify-Hmac-Sha256" => "invalid")

      assert_response :unauthorized
      assert_predicate @store.reload, :active?
      assert_equal "shpat_secret", @store.access_token
    end

    test "app uninstall webhook returns ok for unknown stores" do
      post shopify_app_uninstalled_webhook_path,
        params: payload,
        headers: webhook_headers(shop: "unknown-shop.myshopify.com", payload:)

      assert_response :ok
      assert_predicate @store.reload, :active?
    end

    private

    def payload
      @payload ||= { id: 123456789, domain: "north-pine.myshopify.com" }.to_json
    end

    def webhook_headers(shop:, payload:)
      {
        "CONTENT_TYPE" => "application/json",
        "X-Shopify-Shop-Domain" => shop,
        "X-Shopify-Topic" => "app/uninstalled",
        "X-Shopify-Hmac-Sha256" => hmac_for(payload)
      }
    end

    def hmac_for(payload)
      digest = OpenSSL::HMAC.digest("sha256", @shopify_config.api_secret, payload)
      Base64.strict_encode64(digest)
    end
  end
end
