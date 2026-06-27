# frozen_string_literal: true

module Shopify
  class OauthController < ApplicationController
    rescue_from Shopify::Oauth::Error, with: :reject_oauth_request

    def install
      return render_credentials_error unless shopify_config.credentials_configured

      shop = Shopify::Oauth::Shop.sanitize(params[:shop])
      return head :bad_request unless shop

      state = SecureRandom.hex(24)
      Rails.cache.write(oauth_state_cache_key(state), state, expires_in: 15.minutes)
      cookies.signed[:shopify_oauth_state] = {
        value: state,
        httponly: true,
        same_site: :lax,
        expires: 15.minutes.from_now
      }

      redirect_to Shopify::Oauth::AuthorizationUrl.build(shop:, state:), allow_other_host: true
    end

    def callback
      return render_credentials_error unless shopify_config.credentials_configured

      state = request.query_parameters["state"].to_s
      cached_state = Rails.cache.read(oauth_state_cache_key(state))
      installation = Shopify::Oauth::CallbackHandler.call(
        query_parameters: request.query_parameters,
        state_cookie: cached_state
      )

      Rails.cache.delete(oauth_state_cache_key(state))
      cookies.delete(:shopify_oauth_state)

      redirect_to dashboard_redirect_url(installation.store)
    end

    private

    def shopify_config
      Rails.application.config.x.shopify
    end

    def dashboard_redirect_url(store)
      dashboard_path(shop: store.shopify_domain)
    end

    def reject_oauth_request
      head :unauthorized
    end

    def render_credentials_error
      render plain: "Shopify credentials are not configured", status: :service_unavailable
    end

    def oauth_state_cache_key(state)
      "shopify:oauth:state:#{state}"
    end
  end
end
