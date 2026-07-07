module Ai
  class WinBackEmailDraftGenerator
    SUPPORTED_RULE_KEY = "top_customer_silence"

    def self.call(...)
      new(...).call
    end

    def initialize(result)
      @result = result
    end

    def call
      raise ArgumentError, "win-back drafts require a customer silence opportunity" unless result.rule_key == SUPPORTED_RULE_KEY

      result.update!(win_back_email_draft: draft)
      result.win_back_email_draft
    end

    private

    attr_reader :result

    def draft
      estimated_revenue = result.details["estimated_lost_revenue"].presence || "your previous order value"

      <<~TEXT.strip
        Subject: We saved something for you, {{ customer_first_name }}

        Hi {{ customer_first_name }},

        We noticed it has been a while since your last order with {{ store_name }}. Based on your past purchases, you may like our latest arrivals and returning customer offers.

        As a thank you, use {{ win_back_offer }} on your next order. This segment represents about #{estimated_revenue} in potential repeat revenue, so keep the message personal and useful.

        {{ recommended_products }}

        Thanks,
        {{ store_name }}
      TEXT
    end
  end
end
