# frozen_string_literal: true

require_relative 'test_helper'

class TestProvider < Minitest::Test
  def test_every_provider_is_an_open_router_client
    Provider::PROVIDERS.each do |provider|
      assert_instance_of OpenRouter, Provider.new(provider), provider
    end
  end

  def test_deepseek_defaults_to_pinned_routing
    llm = Provider.new(:deepseek)
    assert_equal 'deepseek/deepseek-v4-pro', llm.model
    assert_equal Provider::DEEPSEEK_ROUTING, llm.routing
  end

  def test_only_deepseek_sends_provider_routing
    refute Provider.new(:gemini).send(:request_body, []).key?(:provider)
    assert_equal Provider::DEEPSEEK_ROUTING, Provider.new(:deepseek).send(:request_body, [])[:provider]
  end

  def test_unknown_provider_raises
    assert_raises(ArgumentError) { Provider.new(:perplexity) }
  end
end
