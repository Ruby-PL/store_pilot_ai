# frozen_string_literal: true

require "test_helper"

module Shopify
  class OauthControllerTest < ActionDispatch::IntegrationTest
    setup do
      @shopify_config = Rails.application.config.x.shopify
      @original_cache = Rails.cache
      @previous_config = {
        api_key: @shopify_config.api_key,
        api_secret: @shopify_config.api_secret,
        scopes: @shopify_config.scopes,
        redirect_uri: @shopify_config.redirect_uri,
        credentials_configured: @shopify_config.credentials_configured
      }

      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      @shopify_config.api_key = "test_client_id"
      @shopify_config.api_secret = "test_client_secret"
      @shopify_config.scopes = %w[read_products read_orders]
      @shopify_config.redirect_uri = "http://www.example.com/auth/shopify/callback"
      @shopify_config.credentials_configured = true
    end

    teardown do
      Rails.cache = @original_cache

      @previous_config.each do |name, value|
        @shopify_config.public_send("#{name}=", value)
      end
    end

    test "install redirects to Shopify authorization URL and stores signed state" do
      authorization_url = start_install

      assert_equal "north-pine.myshopify.com", authorization_url.host
      assert_equal "/admin/oauth/authorize", authorization_url.path

      query = Rack::Utils.parse_query(authorization_url.query)
      assert_equal "test_client_id", query["client_id"]
      assert_equal "read_products,read_orders", query["scope"]
      assert_equal "http://www.example.com/auth/shopify/callback", query["redirect_uri"]
      assert_predicate query["state"], :present?
      assert_includes response.headers["Set-Cookie"], "shopify_oauth_state"
    end

    test "install rejects invalid shop domains" do
      get shopify_install_path(shop: "example.com")

      assert_response :bad_request
    end

    test "callback validates request, stores access token, and redirects to dashboard" do
      state = install_state

      with_access_token_response("shpat_secret_access_token") do
        with_shop_metadata_sync do
          assert_difference -> { Store.count }, 1 do
            get shopify_oauth_callback_path(
              oauth_query(shop: "north-pine.myshopify.com", code: "auth_code", state:)
            )
          end
        end
      end

      store = Store.find_by!(shopify_domain: "north-pine.myshopify.com")
      assert_equal "shpat_secret_access_token", store.access_token
      assert_equal "North Pine", store.name
      assert_equal "owner@north-pine.example", store.owner_email
      assert_equal "EUR", store.currency
      assert_equal "Basic", store.shopify_plan
      assert_redirected_to dashboard_path(shop: "north-pine.myshopify.com")
      assert_includes response.headers["Set-Cookie"], "shopify_oauth_state=;"
    end

    test "install and callback work with cached OAuth state" do
      state = install_state

      assert_not_nil Rails.cache.read(oauth_state_cache_key(state))

      with_access_token_response("shpat_secret_access_token") do
        with_shop_metadata_sync do
          get shopify_oauth_callback_path(
            oauth_query(shop: "north-pine.myshopify.com", code: "auth_code", state:)
          )
        end
      end

      assert_response :redirect
      assert_nil Rails.cache.read(oauth_state_cache_key(state))
      assert_equal "north-pine.myshopify.com", Store.last.shopify_domain
    end

    test "callback rejects invalid hmac" do
      state = install_state

      get shopify_oauth_callback_path(
        shop: "north-pine.myshopify.com",
        code: "auth_code",
        state:,
        timestamp: "1710000000",
        hmac: "invalid"
      )

      assert_response :unauthorized
      assert_equal 0, Store.count
    end

    test "callback rejects mismatched state" do
      install_state

      get shopify_oauth_callback_path(
        oauth_query(shop: "north-pine.myshopify.com", code: "auth_code", state: "different_nonce")
      )

      assert_response :unauthorized
      assert_equal 0, Store.count
    end

    test "callback updates an existing store installation" do
      user = User.create!(email: "existing-merchant@example.com")
      store = user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "old_token",
        name: "Old Name"
      )
      state = install_state

      with_access_token_response("new_token") do
        with_shop_metadata_sync do
          assert_no_difference -> { Store.count } do
            get shopify_oauth_callback_path(
              oauth_query(shop: "north-pine.myshopify.com", code: "auth_code", state:)
            )
          end
        end
      end

      store.reload

      assert_equal "new_token", store.access_token
      assert_equal "North Pine", store.name
      assert_redirected_to dashboard_path(shop: "north-pine.myshopify.com")
    end

    private

    def with_access_token_response(token)
      original_method = Shopify::Oauth::AccessTokenClient.method(:call)
      Shopify::Oauth::AccessTokenClient.define_singleton_method(:call) { |**| token }

      yield
    ensure
      Shopify::Oauth::AccessTokenClient.define_singleton_method(:call, original_method)
    end

    def with_shop_metadata_sync
      original_method = Shopify::ShopMetadataSync.method(:call)
      Shopify::ShopMetadataSync.define_singleton_method(:call) do |store|
        store.update!(
          name: "North Pine",
          owner_email: "owner@north-pine.example",
          currency: "EUR",
          shopify_plan: "Basic"
        )
        store
      end

      yield
    ensure
      Shopify::ShopMetadataSync.define_singleton_method(:call, original_method)
    end

    def start_install
      get shopify_install_path(shop: "north-pine.myshopify.com")

      assert_response :redirect

      URI.parse(response.location)
    end

    def install_state
      authorization_url = start_install
      Rack::Utils.parse_query(authorization_url.query).fetch("state")
    end

    def oauth_query(shop:, code:, state:)
      query = {
        "shop" => shop,
        "code" => code,
        "state" => state,
        "timestamp" => "1710000000"
      }

      query.merge("hmac" => hmac_for(query))
    end

    def hmac_for(query)
      message = query.sort.map { |key, value| "#{key}=#{value}" }.join("&")
      OpenSSL::HMAC.hexdigest("sha256", @shopify_config.api_secret, message)
    end

    def oauth_state_cache_key(state)
      "shopify:oauth:state:#{state}"
    end
  end
end
