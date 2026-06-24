# frozen_string_literal: true

module Shopify
  class AppUninstalledWebhook
    def self.call(shop:)
      new(shop:).call
    end

    def initialize(shop:)
      @shop = Shopify::Oauth::Shop.sanitize(shop)
    end

    def call
      return unless shop

      Store.find_by(shopify_domain: shop)&.mark_uninstalled!
    end

    private

    attr_reader :shop
  end
end
