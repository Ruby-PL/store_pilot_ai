# frozen_string_literal: true

require "test_helper"

module Shopify
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "dashboard responds after OAuth redirect" do
      get dashboard_path(shop: "north-pine.myshopify.com")

      assert_response :success
      assert_includes response.body, "StorePilot AI dashboard"
    end
  end
end
