# frozen_string_literal: true

require "base64"
require "openssl"

module Shopify
  class WebhookVerifier
    def self.valid?(payload:, hmac:)
      new(payload:, hmac:).valid?
    end

    def initialize(payload:, hmac:)
      @payload = payload.to_s
      @hmac = hmac.to_s
    end

    def valid?
      return false if hmac.blank?

      ActiveSupport::SecurityUtils.secure_compare(calculated_hmac, hmac)
    rescue ArgumentError
      false
    end

    private

    attr_reader :payload, :hmac

    def calculated_hmac
      digest = OpenSSL::HMAC.digest(
        OpenSSL::Digest.new("sha256"),
        Rails.application.config.x.shopify.api_secret,
        payload
      )

      Base64.strict_encode64(digest)
    end
  end
end
