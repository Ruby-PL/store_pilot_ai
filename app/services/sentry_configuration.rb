class SentryConfiguration
  ENABLED_ENVIRONMENTS = %w[staging production].freeze

  def self.enabled?
    dsn.present?
  end

  def self.dsn
    ENV["SENTRY_DSN"]
  end

  def self.environment
    ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
  end

  def self.release
    ENV["SENTRY_RELEASE"].presence
  end

  def self.traces_sample_rate
    ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0").to_f
  end
end
