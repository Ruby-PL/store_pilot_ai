# frozen_string_literal: true

require "test_helper"

module Shopify
  class OrderSyncJobTest < ActiveJob::TestCase
    setup do
      @user = User.create!(email: "merchant@example.com")
      @store = @user.stores.create!(
        shopify_domain: "north-pine.myshopify.com",
        access_token: "shpat_secret"
      )
    end

    test "runs order sync" do
      synced_store = nil

      with_order_sync_handler(->(store) { synced_store = store }) do
        with_first_audit_trigger(->(_store) { }) do
          Shopify::OrderSyncJob.perform_now(@store)
        end
      end

      assert_equal @store, synced_store
    end

    test "checks first audit trigger after successful order sync" do
      triggered_store = nil

      with_order_sync_handler(->(store) { store.update!(orders_synced_at: Time.current) }) do
        with_first_audit_trigger(->(store) { triggered_store = store }) do
          Shopify::OrderSyncJob.perform_now(@store)
        end
      end

      assert_equal @store, triggered_store
    end

    test "logs sync errors without raising" do
      logs = capture_logs do
        with_order_sync_handler(->(_store) { raise Shopify::OrderSync::Error, "API unavailable" }) do
          assert_nothing_raised do
            Shopify::OrderSyncJob.perform_now(@store)
          end
        end
      end

      assert_includes logs, "Shopify order sync job failed"
      assert_includes logs, "API unavailable"
    end

    private

    def with_order_sync_handler(handler)
      original_method = Shopify::OrderSync.method(:call)
      Shopify::OrderSync.define_singleton_method(:call, &handler)

      yield
    ensure
      Shopify::OrderSync.define_singleton_method(:call, original_method)
    end

    def with_first_audit_trigger(handler)
      original_method = FirstAuditTrigger.method(:call)
      FirstAuditTrigger.define_singleton_method(:call, &handler)

      yield
    ensure
      FirstAuditTrigger.define_singleton_method(:call, original_method)
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
