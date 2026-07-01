class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "StorePilot <noreply@storepilot.ai>") }
  layout "mailer"
end
