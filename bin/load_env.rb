# Load simple KEY=VALUE entries for development commands without adding a
# runtime dependency. Existing process environment variables always win.
env_file = File.expand_path("../.env", __dir__)

if File.file?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    key, value = line.split("=", 2)
    next unless key&.match?(/\A[A-Z_][A-Z0-9_]*\z/) && value

    value = value[1...-1] if value.length >= 2 && ['"', "'"].include?(value[0]) && value[-1] == value[0]
    ENV[key] ||= value
  end
end
