class HealthController < ActionController::Base
  def show
    database_ok = database_available?
    status = database_ok ? :ok : :service_unavailable

    render json: {
      status: database_ok ? "ok" : "unavailable",
      checks: {
        app: "ok",
        database: database_ok ? "ok" : "unavailable"
      }
    }, status:
  end

  private

  def database_available?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end
end
