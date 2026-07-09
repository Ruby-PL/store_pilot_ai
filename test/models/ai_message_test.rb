require "test_helper"

class AiMessageTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "merchant@example.com")
    store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")
    @conversation = store.ai_conversations.create!(title: "Question")
  end

  test "requires supported role and content" do
    message = @conversation.ai_messages.build(role: "merchant", content: "")

    assert_not message.valid?
    assert_includes message.errors[:role], "is not included in the list"
    assert_includes message.errors[:content], "can't be blank"
  end

  test "tracks non-negative token usage" do
    message = @conversation.ai_messages.build(
      role: "assistant",
      content: "Answer",
      prompt_tokens: -1,
      completion_tokens: -1,
      total_tokens: -1
    )

    assert_not message.valid?
    assert_includes message.errors[:prompt_tokens], "must be greater than or equal to 0"
    assert_includes message.errors[:completion_tokens], "must be greater than or equal to 0"
    assert_includes message.errors[:total_tokens], "must be greater than or equal to 0"
  end
end
