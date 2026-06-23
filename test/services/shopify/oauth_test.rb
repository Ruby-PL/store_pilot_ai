# frozen_string_literal: true

require "test_helper"

module Shopify
  class OauthTest < ActiveSupport::TestCase
    setup do
      @shopify_config = Rails.application.config.x.shopify
      @previous_secret = @shopify_config.api_secret
      @shopify_config.api_secret = "test_client_secret"
    end

    teardown do
      @shopify_config.api_secret = @previous_secret
    end

    test "shop sanitizer accepts full Shopify domains" do
      assert_equal "north-pine.myshopify.com", Oauth::Shop.sanitize(" NORTH-PINE.myshopify.com ")
    end

    test "shop sanitizer accepts shop handles" do
      assert_equal "north-pine.myshopify.com", Oauth::Shop.sanitize("north-pine")
    end

    test "shop sanitizer rejects invalid hostnames" do
      assert_nil Oauth::Shop.sanitize("north-pine.example.com")
    end

    test "hmac verifier validates canonical Shopify query parameters" do
      query = {
        "code" => "auth_code",
        "shop" => "north-pine.myshopify.com",
        "state" => "nonce",
        "timestamp" => "1710000000"
      }
      query["hmac"] = hmac_for(query)

      assert Oauth::HmacVerifier.valid?(query)
    end

    test "hmac verifier rejects tampered parameters" do
      query = {
        "code" => "auth_code",
        "shop" => "north-pine.myshopify.com",
        "state" => "nonce",
        "timestamp" => "1710000000"
      }
      query["hmac"] = hmac_for(query)
      query["shop"] = "other-shop.myshopify.com"

      assert_not Oauth::HmacVerifier.valid?(query)
    end

    private

    def hmac_for(query)
      message = query.sort.map { |key, value| "#{key}=#{value}" }.join("&")
      OpenSSL::HMAC.hexdigest("sha256", @shopify_config.api_secret, message)
    end
  end
end
