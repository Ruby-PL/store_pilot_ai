# frozen_string_literal: true

require "test_helper"

module Shopify
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "dashboard path renders the merchant dashboard shell" do
      get dashboard_path(shop: "north-pine.myshopify.com")

      assert_response :success
      assert_select "h1", "StorePilot AI"
      assert_select ".empty-state h2", "No sync data yet"
    end
  end
end
