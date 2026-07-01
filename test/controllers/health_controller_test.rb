require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns ok when app and database are available" do
    get health_check_path

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "ok", payload.fetch("status")
    assert_equal "ok", payload.dig("checks", "app")
    assert_equal "ok", payload.dig("checks", "database")
  end

  test "returns unavailable without exposing database error details" do
    connection = ActiveRecord::Base.connection
    original_execute = connection.method(:execute)

    connection.define_singleton_method(:execute) do |*_args|
      raise ActiveRecord::ConnectionNotEstablished, "postgres://secret@example"
    end

    begin
      get health_check_path
    ensure
      connection.define_singleton_method(:execute, original_execute)
    end

    assert_response :service_unavailable

    payload = JSON.parse(response.body)
    assert_equal "unavailable", payload.fetch("status")
    assert_equal "ok", payload.dig("checks", "app")
    assert_equal "unavailable", payload.dig("checks", "database")
    assert_no_match(/postgres|secret|example/, response.body)
  end
end
