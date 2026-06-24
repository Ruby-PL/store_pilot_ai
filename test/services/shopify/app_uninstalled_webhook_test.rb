# frozen_string_literal: true

require "test_helper"

module Shopify
  class AppUninstalledWebhookTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "marks matching store uninstalled" do
      AppUninstalledWebhook.call(shop: "north-pine.myshopify.com")

      assert_not @store.reload.active?
      assert_nil @store.access_token
      assert_predicate @store.uninstalled_at, :present?
    end

    test "ignores unknown stores" do
      assert_nothing_raised do
        AppUninstalledWebhook.call(shop: "unknown-shop.myshopify.com")
      end

      assert_predicate @store.reload, :active?
    end

    test "ignores invalid shop domains" do
      assert_nothing_raised do
        AppUninstalledWebhook.call(shop: "example.com")
      end

      assert_predicate @store.reload, :active?
    end
  end
end
