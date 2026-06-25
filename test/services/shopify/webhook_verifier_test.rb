# frozen_string_literal: true

require "test_helper"

module Shopify
  class WebhookVerifierTest < ActiveSupport::TestCase
    setup do
      @shopify_config = Rails.application.config.x.shopify
      @previous_secret = @shopify_config.api_secret
      @shopify_config.api_secret = "test_client_secret"
    end

    teardown do
      @shopify_config.api_secret = @previous_secret
    end

    test "validates Shopify webhook HMAC" do
      payload = { shop_domain: "north-pine.myshopify.com" }.to_json

      assert WebhookVerifier.valid?(payload:, hmac: hmac_for(payload))
    end

    test "rejects tampered Shopify webhook HMAC" do
      payload = { shop_domain: "north-pine.myshopify.com" }.to_json

      assert_not WebhookVerifier.valid?(payload: payload.gsub("north-pine", "south-pine"), hmac: hmac_for(payload))
    end

    test "rejects missing Shopify webhook HMAC" do
      payload = { shop_domain: "north-pine.myshopify.com" }.to_json

      assert_not WebhookVerifier.valid?(payload:, hmac: nil)
    end

    private

    def hmac_for(payload)
      digest = OpenSSL::HMAC.digest("sha256", @shopify_config.api_secret, payload)
      Base64.strict_encode64(digest)
    end
  end
end
