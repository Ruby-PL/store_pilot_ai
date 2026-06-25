# frozen_string_literal: true

require "test_helper"

class BackgroundJobInfrastructureTest < ActiveJob::TestCase
  test "example background job can be enqueued" do
    assert_enqueued_with(job: ExampleBackgroundJob, args: [ "smoke-test" ]) do
      ExampleBackgroundJob.perform_later("smoke-test")
    end
  end

  test "product sync can run in background" do
    store = create_store

    assert_enqueued_with(job: Shopify::ProductSyncJob, args: [ store ]) do
      Shopify::ProductSyncJob.perform_later(store)
    end
  end

  test "order sync can run in background" do
    store = create_store

    assert_enqueued_with(job: Shopify::OrderSyncJob, args: [ store ]) do
      Shopify::OrderSyncJob.perform_later(store)
    end
  end

  private

  def create_store
    user = User.create!(email: "merchant-#{SecureRandom.hex(4)}@example.com")
    user.stores.create!(shopify_domain: "store-#{SecureRandom.hex(4)}.myshopify.com", access_token: "shpat_secret")
  end
end
