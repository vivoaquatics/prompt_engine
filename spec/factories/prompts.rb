FactoryBot.define do
  factory :prompt, class: 'PromptEngine::Prompt' do
    sequence(:name) { |n| "Test Prompt #{n}" }
    description { "A test prompt for RSpec" }
    content { "Tell me about {{topic}}" }
    system_message { "You are a helpful assistant." }
    model { "gpt-4" }
    temperature { 0.7 }
    max_tokens { 1000 }
    status { "draft" }
    metadata { {} }
    reasoning_effort { nil }

    # The base factory stays on a non-reasoning model ("gpt-4") deliberately,
    # so every existing spec built on :prompt is unaffected by the
    # reasoning_effort inclusion validation. Use this trait to exercise a
    # reasoning-capable model + a valid stored effort.
    trait :with_reasoning do
      model { "gpt-5.6-sol" }
      reasoning_effort { "high" }
    end
  end
end
