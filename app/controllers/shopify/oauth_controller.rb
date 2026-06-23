# frozen_string_literal: true

module Shopify
  class OauthController < ApplicationController
    rescue_from Shopify::Oauth::Error, with: :reject_oauth_request

    def install
      return render_credentials_error unless shopify_config.credentials_configured

      shop = Shopify::Oauth::Shop.sanitize(params[:shop])
      return head :bad_request unless shop

      state = SecureRandom.hex(24)
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

      installation = Shopify::Oauth::CallbackHandler.call(
        query_parameters: request.query_parameters,
        state_cookie: cookies.signed[:shopify_oauth_state]
      )

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
  end
end
