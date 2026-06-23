# frozen_string_literal: true

shopify = Rails.application.config.x.shopify

shopify.api_key = ENV["SHOPIFY_API_KEY"].presence
shopify.api_secret = ENV["SHOPIFY_API_SECRET"].presence
shopify.app_url = ENV.fetch("SHOPIFY_APP_URL", "http://localhost:#{ENV.fetch("PORT", 3005)}")
shopify.redirect_uri = ENV.fetch("SHOPIFY_REDIRECT_URI", "#{shopify.app_url}/auth/shopify/callback")
shopify.scopes = ENV.fetch("SHOPIFY_SCOPES", "read_products,read_orders").split(",").map(&:strip).reject(&:blank?)

shopify.missing_credentials = {
  api_key: shopify.api_key,
  api_secret: shopify.api_secret
}.filter_map { |name, value| name if value.blank? }
shopify.credentials_configured = shopify.missing_credentials.empty?

if ENV["SHOPIFY_REQUIRE_CREDENTIALS"] == "true" && !shopify.credentials_configured
  missing = shopify.missing_credentials.map { |name| "SHOPIFY_#{name.to_s.upcase}" }.join(", ")

  raise "Missing required Shopify credentials: #{missing}"
end
