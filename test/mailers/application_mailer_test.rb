require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  class TestMailer < ApplicationMailer
    def test_email
      mail(to: "merchant@example.com", subject: "Test", body: "Hello")
    end
  end

  test "uses configured default sender" do
    previous_mailer_from = ENV["MAILER_FROM"]
    ENV["MAILER_FROM"] = "StorePilot <support@storepilot.ai>"

    mail = TestMailer.test_email

    assert_equal [ "support@storepilot.ai" ], mail.from
    assert_equal "StorePilot", mail[:from].display_names.first
  ensure
    previous_mailer_from.nil? ? ENV.delete("MAILER_FROM") : ENV["MAILER_FROM"] = previous_mailer_from
  end
end
