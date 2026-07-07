require "test_helper"

class FirstAuditTriggerTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "merchant@example.com")
    @store = @user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "does not enqueue until products and orders are synced" do
    @store.update!(products_synced_at: Time.current)

    assert_no_enqueued_jobs only: AuditJob do
      assert_not FirstAuditTrigger.call(@store)
    end
  end

  test "enqueues first audit when both syncs are complete" do
    @store.update!(products_synced_at: Time.current, orders_synced_at: Time.current)

    assert_enqueued_with(job: AuditJob, args: [ @store ]) do
      assert FirstAuditTrigger.call(@store)
    end
  end

  test "does not enqueue when an audit already exists" do
    @store.update!(products_synced_at: Time.current, orders_synced_at: Time.current)
    @store.audit_runs.create!(started_at: Time.current)

    assert_no_enqueued_jobs only: AuditJob do
      assert_not FirstAuditTrigger.call(@store)
    end
  end
end
