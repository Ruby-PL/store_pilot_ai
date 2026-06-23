# frozen_string_literal: true

require "test_helper"

module Shopify
  module Admin
    class GraphqlClientTest < ActiveSupport::TestCase
      setup do
        @shopify_config = Rails.application.config.x.shopify
        @previous_api_version = @shopify_config.api_version
        @shopify_config.api_version = "2026-04"
      end

      teardown do
        @shopify_config.api_version = @previous_api_version
      end

      test "posts GraphQL queries to the Shopify Admin API" do
        captured_request = nil
        captured_host = nil
        response = successful_response("data" => { "shop" => { "name" => "North Pine" } })

        data = nil

        with_http_response(response, handler: ->(host, request) {
          captured_host = host
          captured_request = request
        }) do
          data = GraphqlClient.new(
            shop: "north-pine.myshopify.com",
            access_token: "shpat_secret"
          ).query("query { shop { name } }")
        end

        assert_equal({ "shop" => { "name" => "North Pine" } }, data)
        assert_equal "north-pine.myshopify.com", captured_host
        assert_equal "/admin/api/2026-04/graphql.json", captured_request.path
        assert_equal "shpat_secret", captured_request["X-Shopify-Access-Token"]
        assert_equal "application/json", captured_request["Content-Type"]
      end

      test "raises on GraphQL errors" do
        response = successful_response("errors" => [ { "message" => "Unauthorized" } ])

        with_http_response(response) do
          assert_raises GraphqlClient::Error do
            GraphqlClient.new(
              shop: "north-pine.myshopify.com",
              access_token: "shpat_secret"
            ).query("query { shop { name } }")
          end
        end
      end

      private

      def successful_response(payload)
        Net::HTTPSuccess.new("1.1", "200", "OK").tap do |response|
          response.instance_variable_set(:@body, JSON.generate(payload))
          response.instance_variable_set(:@read, true)
        end
      end

      def with_http_response(response, handler: ->(_host, _request) { })
        original_start = Net::HTTP.method(:start)

        Net::HTTP.define_singleton_method(:start) do |host, _port, use_ssl:, &block|
          http = Object.new
          http.define_singleton_method(:request) do |actual_request|
            handler.call(host, actual_request)
            response
          end

          raise "Expected HTTPS request" unless use_ssl

          block.call(http)
        end

        yield
      ensure
        Net::HTTP.define_singleton_method(:start, original_start)
      end
    end
  end
end
