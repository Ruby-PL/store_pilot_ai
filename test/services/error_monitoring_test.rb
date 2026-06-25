require "test_helper"

class ErrorMonitoringTest < ActiveSupport::TestCase
  test "captures exceptions through Sentry with context" do
    exception = RuntimeError.new("Sentry smoke test")
    captured = nil
    original_capture_exception = Sentry.method(:capture_exception)

    Sentry.define_singleton_method(:capture_exception) do |error, extra:|
      captured = [ error, extra ]
    end

    ErrorMonitoring.capture_exception(exception, context: { source: "test" })

    assert_equal exception, captured.first
    assert_equal({ source: "test" }, captured.second)
  ensure
    Sentry.define_singleton_method(:capture_exception, original_capture_exception)
  end
end
