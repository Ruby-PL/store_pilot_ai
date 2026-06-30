require Rails.root.join("app/services/sentry_configuration")

if SentryConfiguration.enabled?
  Sentry.init do |config|
    config.dsn = SentryConfiguration.dsn
    config.environment = SentryConfiguration.environment
    config.enabled_environments = SentryConfiguration::ENABLED_ENVIRONMENTS
    config.release = SentryConfiguration.release if SentryConfiguration.release.present?
    config.traces_sample_rate = SentryConfiguration.traces_sample_rate
  end
end
