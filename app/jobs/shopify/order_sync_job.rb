# frozen_string_literal: true

module Shopify
  class OrderSyncJob < ApplicationJob
    queue_as :default

    def perform(store)
      Shopify::OrderSync.call(store)
      FirstAuditTrigger.call(store.reload)
    rescue Shopify::OrderSync::Error => error
      Rails.logger.error("Shopify order sync job failed for store_id=#{store.id}: #{error.message}")
    end
  end
end
