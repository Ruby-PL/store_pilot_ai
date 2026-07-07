# frozen_string_literal: true

module Shopify
  class ProductSyncJob < ApplicationJob
    queue_as :default

    def perform(store)
      Shopify::ProductSync.call(store)
      FirstAuditTrigger.call(store.reload)
    rescue Shopify::ProductSync::Error => error
      Rails.logger.error("Shopify product sync job failed for store_id=#{store.id}: #{error.message}")
    end
  end
end
