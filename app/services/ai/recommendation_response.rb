module Ai
  RecommendationResponse = Data.define(:text, :provider, :model, :prompt_tokens, :completion_tokens, :total_tokens)
end
