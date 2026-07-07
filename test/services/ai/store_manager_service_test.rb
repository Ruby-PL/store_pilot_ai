require "test_helper"

module Ai
  class StoreManagerServiceTest < ActiveSupport::TestCase
    setup do
      user = User.create!(email: "merchant@example.com")
      @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    end

    test "builds context, calls provider and stores response token usage" do
      provider = StaticProvider.new(
        RecommendationResponse.new(
          text: "Fix the highest priority revenue opportunity first.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 11,
          completion_tokens: 7,
          total_tokens: 18
        )
      )

      conversation = StoreManagerService.call(
        store: @store,
        question: "What should I fix first?",
        provider:
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "What should I fix first?", messages.first.content
      assert_equal "Fix the highest priority revenue opportunity first.", messages.second.content
      assert_equal 18, messages.second.total_tokens
      assert_equal "What should I fix first?", provider.context.fetch(:question)
      assert_equal "north-pine.myshopify.com", provider.context.dig(:store_context, :store, :shopify_domain)
    end

    test "stores graceful fallback when provider fails" do
      conversation = StoreManagerService.call(
        store: @store,
        question: "Why are sales down?",
        provider: FailingProvider.new
      )

      messages = conversation.ai_messages.order(:created_at)
      assert_equal [ "user", "assistant" ], messages.pluck(:role)
      assert_equal "Why are sales down?", messages.first.content
      assert_equal StoreManagerService::FALLBACK_RESPONSE, messages.second.content
      assert_equal 0, messages.second.total_tokens
    end

    test "can append to an existing conversation" do
      conversation = @store.ai_conversations.create!(title: "Existing")

      StoreManagerService.call(
        store: @store,
        question: "What should I promote?",
        conversation:,
        provider: StaticProvider.new(RecommendationResponse.new(
          text: "Promote best sellers with stock.",
          provider: "test",
          model: "test-model",
          prompt_tokens: 3,
          completion_tokens: 4,
          total_tokens: 7
        ))
      )

      assert_equal conversation, @store.ai_conversations.sole
      assert_equal 2, conversation.ai_messages.count
    end

    private

    class StaticProvider
      attr_reader :context

      def initialize(response)
        @response = response
      end

      def complete_recommendation(context:)
        @context = context
        @response
      end
    end

    class FailingProvider
      def complete_recommendation(context:)
        raise "provider failed"
      end
    end
  end
end
