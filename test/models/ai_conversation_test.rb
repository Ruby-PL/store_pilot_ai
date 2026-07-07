require "test_helper"

class AiConversationTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    @store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
  end

  test "belongs to a store and has messages" do
    conversation = @store.ai_conversations.create!(title: "What should I fix first?")
    message = conversation.ai_messages.create!(role: "user", content: "What should I fix first?")

    assert_equal @store, conversation.store
    assert_equal [ message ], conversation.ai_messages.to_a
  end

  test "requires title" do
    conversation = @store.ai_conversations.build(title: "")

    assert_not conversation.valid?
    assert_includes conversation.errors[:title], "can't be blank"
  end
end
