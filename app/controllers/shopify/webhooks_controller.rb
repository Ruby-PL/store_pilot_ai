# frozen_string_literal: true

module Shopify
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def app_uninstalled
      return head :service_unavailable unless shopify_config.credentials_configured
      return head :unauthorized unless verified_webhook?

      Shopify::AppUninstalledWebhook.call(shop: request.headers["X-Shopify-Shop-Domain"])

      head :ok
    end

    private

    def shopify_config
      Rails.application.config.x.shopify
    end

    def verified_webhook?
      Shopify::WebhookVerifier.valid?(
        payload: request.raw_post,
        hmac: request.headers["X-Shopify-Hmac-Sha256"]
      )
    end
  end
end
