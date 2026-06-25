if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = Rails.env
    config.enabled_environments = %w[production staging]
    config.release = ENV["SENTRY_RELEASE"] if ENV["SENTRY_RELEASE"].present?
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0").to_f
  end
end
