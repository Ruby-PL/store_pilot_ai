module Ai
  module PromptTemplate
    NAME = "merchant_recommendation".freeze
    VERSION = "v1".freeze
    GUARDRAILS = [
      "Do not invent facts that are not present in the provided context.",
      "If the data is insufficient, say exactly what is missing.",
      "Do not recommend automatic price changes without explicit merchant review.",
      "Do not expose unnecessary customer personal data."
    ].freeze

    def self.metadata
      {
        name: NAME,
        version: VERSION,
        guardrails: GUARDRAILS
      }
    end

    def self.system_prompt
      [
        "Write concise, merchant-friendly ecommerce recommendations from structured context.",
        "Do not mention internal IDs.",
        GUARDRAILS.join(" ")
      ].join(" ")
    end
  end
end
