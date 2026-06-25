# frozen_string_literal: true

class ExampleBackgroundJob < ApplicationJob
  queue_as :default

  def perform(message = "ok")
    Rails.logger.info("Example background job completed message=#{message}")
  end
end
