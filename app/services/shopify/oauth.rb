# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Shopify
  module Oauth
    Error = Class.new(StandardError)
    InvalidShopError = Class.new(Error)
    InvalidHmacError = Class.new(Error)
    InvalidStateError = Class.new(Error)
    TokenExchangeError = Class.new(Error)
    MetadataSyncError = Class.new(Error)

    class Shop
      DOMAIN_FORMAT = Store::SHOPIFY_DOMAIN_FORMAT

      def self.sanitize(value)
        shop = value.to_s.strip.downcase
        return if shop.blank?

        shop += ".myshopify.com" unless shop.end_with?(".myshopify.com")
        return unless shop.match?(DOMAIN_FORMAT)

        shop
      end
    end

    class AuthorizationUrl
      def self.build(shop:, state:)
        config = Rails.application.config.x.shopify

        URI::HTTPS.build(
          host: shop,
          path: "/admin/oauth/authorize",
          query: Rack::Utils.build_query(
            client_id: config.api_key,
            scope: config.scopes.join(","),
            redirect_uri: config.redirect_uri,
            state:
          )
        ).to_s
      end
    end

    class HmacVerifier
      EXCLUDED_PARAMETERS = %w[hmac signature].freeze

      def self.valid?(query_parameters)
        hmac = query_parameters["hmac"].to_s
        secret = Rails.application.config.x.shopify.api_secret
        return false if hmac.blank? || secret.blank?

        digest = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"),
          secret,
          canonical_message(query_parameters)
        )

        ActiveSupport::SecurityUtils.secure_compare(digest, hmac)
      rescue ArgumentError, TypeError
        false
      end

      def self.canonical_message(query_parameters)
        query_parameters
          .except(*EXCLUDED_PARAMETERS)
          .sort
          .map { |key, value| "#{key}=#{Array(value).join(",")}" }
          .join("&")
      end
    end

    class AccessTokenClient
      def self.call(shop:, code:)
        new(shop:, code:).call
      end

      def initialize(shop:, code:)
        @shop = shop
        @code = code
      end

      def call
        response = Net::HTTP.post_form(access_token_uri, request_parameters)
        raise TokenExchangeError, "Shopify token exchange failed" unless response.is_a?(Net::HTTPSuccess)

        token = JSON.parse(response.body).fetch("access_token")
        raise TokenExchangeError, "Shopify token response did not include an access token" if token.blank?

        token
      rescue JSON::ParserError, KeyError
        raise TokenExchangeError, "Shopify token response was invalid"
      end

      private

      attr_reader :shop, :code

      def access_token_uri
        URI::HTTPS.build(host: shop, path: "/admin/oauth/access_token")
      end

      def request_parameters
        config = Rails.application.config.x.shopify

        {
          client_id: config.api_key,
          client_secret: config.api_secret,
          code:
        }
      end
    end

    class CallbackHandler
      Result = Data.define(:store)

      def self.call(query_parameters:, state_cookie:)
        new(query_parameters:, state_cookie:).call
      end

      def initialize(query_parameters:, state_cookie:)
        @query_parameters = query_parameters
        @state_cookie = state_cookie
      end

      def call
        validate!

        token = AccessTokenClient.call(shop:, code:)
        store = persist_store!(token)

        Result.new(store:)
      end

      private

      attr_reader :query_parameters, :state_cookie

      def validate!
        raise InvalidShopError unless shop
        raise InvalidStateError if state.blank? || state_cookie.blank? || state != state_cookie
        raise InvalidHmacError unless HmacVerifier.valid?(query_parameters)
        raise Error, "Missing authorization code" if code.blank?
      end

      def shop
        @shop ||= Shop.sanitize(query_parameters["shop"])
      end

      def state
        query_parameters["state"].to_s
      end

      def code
        query_parameters["code"].to_s
      end

      def persist_store!(token)
        store = Store.find_or_initialize_by(shopify_domain: shop)
        store.user ||= user_for_shop
        store.access_token = token
        store.active = true
        store.uninstalled_at = nil
        store.save!
        Shopify::ShopMetadataSync.call(store)
      rescue Shopify::Admin::GraphqlClient::Error, Shopify::ShopMetadataSync::Error => error
        raise MetadataSyncError, error.message
      end

      def user_for_shop
        User.find_or_create_by!(email: "#{shop.delete_suffix(".myshopify.com")}@storepilot.local")
      end
    end
  end
end
