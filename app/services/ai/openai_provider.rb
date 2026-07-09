require "net/http"
require "json"

module Ai
  class OpenaiProvider < Provider
    ENDPOINT = URI("https://api.openai.com/v1/responses")
    DEFAULT_MODEL = "gpt-4.1-mini"

    def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV.fetch("OPENAI_MODEL", DEFAULT_MODEL))
      @api_key = api_key
      @model = model
    end

    def complete_recommendation(context:)
      raise "OPENAI_API_KEY is not configured" if api_key.blank?

      response = Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port, use_ssl: true) do |http|
        http.request(build_request(context))
      end
      body = JSON.parse(response.body)
      raise "OpenAI request failed with #{response.code}: #{body}" unless response.is_a?(Net::HTTPSuccess)

      RecommendationResponse.new(
        text: extract_text(body),
        provider: "openai",
        model: model,
        prompt_tokens: body.dig("usage", "input_tokens").to_i,
        completion_tokens: body.dig("usage", "output_tokens").to_i,
        total_tokens: body.dig("usage", "total_tokens").to_i
      )
    end

    private

    attr_reader :api_key, :model

    def build_request(context)
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = {
        model:,
        input: [
          {
            role: "system",
            content: PromptTemplate.system_prompt
          },
          {
            role: "user",
            content: JSON.generate(context.merge(prompt_template: PromptTemplate.metadata))
          }
        ]
      }.to_json
      request
    end

    def extract_text(body)
      body.fetch("output", []).flat_map { |item| item.fetch("content", []) }
        .filter_map { |content| content["text"] }
        .join("\n")
        .presence || body["output_text"].to_s
    end
  end
end
