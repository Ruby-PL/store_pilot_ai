module ErrorMonitoring
  module_function

  def capture_exception(exception, context: {})
    Rails.logger.error("Captured exception for monitoring: #{exception.class}: #{exception.message}")
    return unless defined?(Sentry)

    Sentry.capture_exception(exception, extra: context)
  end
end
