# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Shopify
  module Admin
    class GraphqlClient
      Error = Class.new(StandardError)

      def initialize(shop:, access_token:)
        @shop = Shopify::Oauth::Shop.sanitize(shop)
        @access_token = access_token

        raise Error, "Invalid Shopify shop domain" if @shop.blank?
        raise Error, "Missing Shopify access token" if @access_token.blank?
      end

      def query(query, variables: {})
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["X-Shopify-Access-Token"] = access_token
        request.body = JSON.generate(query:, variables:)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise Error, "Shopify GraphQL request failed" unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        errors = payload["errors"]
        raise Error, "Shopify GraphQL response contained errors" if errors.present?

        payload.fetch("data")
      rescue JSON::ParserError, KeyError
        raise Error, "Shopify GraphQL response was invalid"
      end

      private

      attr_reader :shop, :access_token

      def uri
        @uri ||= URI::HTTPS.build(
          host: shop,
          path: "/admin/api/#{Rails.application.config.x.shopify.api_version}/graphql.json"
        )
      end
    end
  end
end
