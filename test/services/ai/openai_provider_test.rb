require "test_helper"

module Ai
  class OpenaiProviderTest < ActiveSupport::TestCase
    test "posts summarized context to responses endpoint and returns token usage" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      response.define_singleton_method(:body) do
        {
          output: [
            { content: [ { text: "Improve product pages with clearer recommendations." } ] }
          ],
          usage: {
            input_tokens: 12,
            output_tokens: 8,
            total_tokens: 20
          }
        }.to_json
      end

      request_body = nil
      with_http_response(response, handler: ->(_host, request) { request_body = JSON.parse(request.body) }) do
        result = OpenaiProvider.new(api_key: "test-key", model: "gpt-test").complete_recommendation(
          context: { title: "SEO issue" }
        )

        assert_equal "Improve product pages with clearer recommendations.", result.text
        assert_equal "openai", result.provider
        assert_equal "gpt-test", result.model
        assert_equal 12, result.prompt_tokens
        assert_equal 8, result.completion_tokens
        assert_equal 20, result.total_tokens
      end

      assert_equal "gpt-test", request_body.fetch("model")
      assert_includes request_body.fetch("input").first.fetch("content"), "Do not invent facts"
      assert_includes request_body.fetch("input").first.fetch("content"), "automatic price changes"
      assert_includes request_body.fetch("input").last.fetch("content"), "SEO issue"
      assert_includes request_body.fetch("input").last.fetch("content"), "prompt_template"
      assert_includes request_body.fetch("input").last.fetch("content"), "merchant_recommendation"
      assert_includes request_body.fetch("input").last.fetch("content"), "\"version\":\"v1\""
    end

    test "requires an API key" do
      error = assert_raises(RuntimeError) do
        OpenaiProvider.new(api_key: nil).complete_recommendation(context: {})
      end

      assert_includes error.message, "OPENAI_API_KEY"
    end

    private

    def with_http_response(response, handler:)
      original_start = Net::HTTP.method(:start)

      Net::HTTP.define_singleton_method(:start) do |host, port, use_ssl:, &block|
        http = Object.new
        http.define_singleton_method(:request) do |request|
          handler.call(host, request)
          response
        end
        block.call(http)
      end

      yield
    ensure
      Net::HTTP.define_singleton_method(:start, original_start)
    end
  end
end
