# frozen_string_literal: true

require "test_helper"

module Shopify
  class ProductSyncJobTest < ActiveJob::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret"
      )
    end

    test "runs product sync" do
      synced_store = nil

      with_product_sync_handler(->(store) { synced_store = store }) do
        Shopify::ProductSyncJob.perform_now(@store)
      end

      assert_equal @store, synced_store
    end

    test "logs sync errors without raising" do
      logs = capture_logs do
        with_product_sync_handler(->(_store) { raise Shopify::ProductSync::Error, "API unavailable" }) do
          assert_nothing_raised do
            Shopify::ProductSyncJob.perform_now(@store)
          end
        end
      end

      assert_includes logs, "Shopify product sync job failed"
      assert_includes logs, "API unavailable"
    end

    private

    def with_product_sync_handler(handler)
      original_method = Shopify::ProductSync.method(:call)
      Shopify::ProductSync.define_singleton_method(:call, &handler)

      yield
    ensure
      Shopify::ProductSync.define_singleton_method(:call, original_method)
    end

    def capture_logs
      io = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)

      yield

      io.string
    ensure
      Rails.logger = original_logger
    end
  end
end
