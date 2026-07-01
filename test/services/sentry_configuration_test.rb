require "test_helper"

class SentryConfigurationTest < ActiveSupport::TestCase
  test "is disabled without a DSN" do
    with_env("SENTRY_DSN" => nil) do
      assert_not SentryConfiguration.enabled?
    end
  end

  test "uses explicit Sentry environment when provided" do
    with_env("SENTRY_DSN" => "https://example@sentry.io/1", "SENTRY_ENVIRONMENT" => "staging") do
      assert SentryConfiguration.enabled?
      assert_equal "staging", SentryConfiguration.environment
    end
  end

  test "falls back to Rails environment" do
    with_env("SENTRY_ENVIRONMENT" => nil) do
      assert_equal Rails.env, SentryConfiguration.environment
    end
  end

  test "parses optional release and trace sample rate" do
    with_env("SENTRY_RELEASE" => "abc123", "SENTRY_TRACES_SAMPLE_RATE" => "0.25") do
      assert_equal "abc123", SentryConfiguration.release
      assert_equal 0.25, SentryConfiguration.traces_sample_rate
    end
  end

  private

  def with_env(values)
    previous_values = values.transform_values { |_value| nil }
    values.each do |key, value|
      previous_values[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    previous_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
