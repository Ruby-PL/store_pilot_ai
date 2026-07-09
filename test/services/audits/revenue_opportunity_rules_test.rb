require "test_helper"

module Audits
  class RevenueOpportunityRulesTest < ActiveSupport::TestCase
    test "core revenue opportunity rules have focused test coverage" do
      expected_tests = %w[
        test/services/audits/bundle_opportunity_rule_test.rb
        test/services/audits/dead_stock_rule_test.rb
        test/services/audits/inventory_risk_rule_test.rb
        test/services/audits/review_gap_rule_test.rb
        test/services/audits/top_customer_silence_rule_test.rb
        test/services/audits/repeat_buyer_analysis_rule_test.rb
        test/services/audits/price_elasticity_rule_test.rb
      ]

      expected_tests.each do |path|
        assert File.exist?(Rails.root.join(path)), "#{path} should exist"
      end
    end
  end
end
