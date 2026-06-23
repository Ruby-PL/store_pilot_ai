# frozen_string_literal: true

module Shopify
  class DashboardController < ApplicationController
    def show
      @store = Store.find_by(shopify_domain: Shopify::Oauth::Shop.sanitize(params[:shop]))

      render plain: "StorePilot AI dashboard"
    end
  end
end
