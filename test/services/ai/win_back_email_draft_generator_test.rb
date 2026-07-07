require "test_helper"

module Ai
  class WinBackEmailDraftGeneratorTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
      audit_run = store.audit_runs.create!(started_at: Time.current)
      @result = audit_run.audit_results.create!(
        rule_key: "top_customer_silence",
        title: "High-value customers have gone silent",
        status: "warning",
        severity: "high",
        category: "revenue",
        description: "Customers are inactive.",
        recommendation: "Send a win-back offer.",
        details: {
          estimated_lost_revenue: "150.00"
        }
      )
    end

    test "stores a draft with personalization placeholders" do
      draft = WinBackEmailDraftGenerator.call(@result)

      assert_equal draft, @result.reload.win_back_email_draft
      assert_includes draft, "{{ customer_first_name }}"
      assert_includes draft, "{{ store_name }}"
      assert_includes draft, "{{ win_back_offer }}"
      assert_includes draft, "{{ recommended_products }}"
      assert_includes draft, "150.00"
    end

    test "rejects non customer silence opportunities" do
      @result.update!(rule_key: "bundle_opportunity")

      assert_raises ArgumentError do
        WinBackEmailDraftGenerator.call(@result)
      end
    end
  end
end
