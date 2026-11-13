# frozen_string_literal: true

require_relative 'test_helper'

class ResponseTest < Minitest::Test
  def openai_json(content: 'hello', input: 100, output: 50, total: 150, tool_calls: nil)
    {
      'choices' => [{ 'message' => { 'content' => content, 'tool_calls' => tool_calls } }],
      'usage' => { 'prompt_tokens' => input, 'completion_tokens' => output, 'total_tokens' => total }
    }.to_json
  end

  def open_router_json(content: 'or', input: 300, output: 100, total: 400, cost: 0.02)
    {
      'choices' => [{ 'message' => { 'content' => content, 'tool_calls' => nil } }],
      'usage' => {
        'prompt_tokens' => input,
        'completion_tokens' => output,
        'total_tokens' => total,
        'cost' => cost
      }
    }.to_json
  end

  # ---------------------------------------------------------------------------
  # content extraction
  # ---------------------------------------------------------------------------

  def test_content_openai_provider
    r = Response.new(:openai, json: openai_json(content: 'test content'))
    assert_equal 'test content', r.content
  end

  def test_content_open_router_provider
    r = Response.new(:open_router, json: open_router_json(content: 'or content'))
    assert_equal 'or content', r.content
  end

  def test_content_anthropic_routes_to_openai_compatible
    r = Response.new(:anthropic, json: openai_json(content: 'anthropic content'))
    assert_equal 'anthropic content', r.content
  end

  def test_content_gemini_provider
    r = Response.new(:gemini, json: open_router_json(content: 'gemini content'))
    assert_equal 'gemini content', r.content
  end

  # ---------------------------------------------------------------------------
  # token counts
  # ---------------------------------------------------------------------------

  def test_input_tokens_openai
    r = Response.new(:openai, json: openai_json(input: 123))
    assert_equal 123, r.input_tokens
  end

  def test_output_tokens_openai
    r = Response.new(:openai, json: openai_json(output: 77))
    assert_equal 77, r.output_tokens
  end

  def test_total_tokens_openai_from_usage_field
    r = Response.new(:openai, json: openai_json(total: 200))
    assert_equal 200, r.total_tokens
  end

  def test_total_tokens_falls_back_to_sum_when_missing
    json = { 'choices' => [{ 'message' => { 'content' => 'x', 'tool_calls' => nil } }],
             'usage' => { 'prompt_tokens' => 40, 'completion_tokens' => 20 } }.to_json
    r = Response.new(:openai, json: json)
    assert_equal 60, r.total_tokens
  end

  def test_tokens_default_to_zero_for_empty_json
    r = Response.new(:openai, json: '{}')
    assert_equal 0, r.input_tokens
    assert_equal 0, r.output_tokens
    assert_equal 0, r.total_tokens
  end

  # ---------------------------------------------------------------------------
  # cost calculations
  # ---------------------------------------------------------------------------

  def test_open_router_cost_from_usage_field
    r = Response.new(:open_router, json: open_router_json(cost: 0.03))
    assert_in_delta 0.03, r.cost, 0.0001
  end

  def test_anthropic_cost_routed_to_open_router
    r = Response.new(:anthropic, json: open_router_json(cost: 0.05))
    assert_in_delta 0.05, r.cost, 0.0001
  end

  def test_openai_cost_routed_to_open_router
    r = Response.new(:openai, json: open_router_json(cost: 0.01))
    assert_in_delta 0.01, r.cost, 0.0001
  end

  def test_cost_uses_open_router_usage_for_every_provider
    %i[deepseek gemini openai anthropic].each do |provider|
      r = Response.new(provider, json: { 'usage' => { 'cost' => 0.12 } }.to_json)
      assert_in_delta 0.12, r.cost, 0.0001, provider
    end
  end

  def test_host_reads_open_router_provider_field
    assert_equal 'DeepSeek', Response.new(:deepseek, json: { 'provider' => 'DeepSeek' }.to_json).host
    assert_nil Response.new(:deepseek, json: '{}').host
  end

  # Real OpenRouter usage: cost_details restates the same upstream charge.
  def usage_json(is_byok:)
    { 'usage' => {
      'cost' => 0.0283088, 'is_byok' => is_byok,
      'cost_details' => { 'upstream_inference_cost' => 0.0283088,
                          'upstream_inference_prompt_cost' => 0.009295,
                          'upstream_inference_completions_cost' => 0.0190138 }
    } }.to_json
  end

  def test_cost_does_not_double_count_cost_details
    assert_in_delta 0.0283088, Response.new(:deepseek, json: usage_json(is_byok: false)).cost, 1e-9
  end

  def test_byok_cost_adds_upstream_charge
    assert_in_delta 0.0566176, Response.new(:deepseek, json: usage_json(is_byok: true)).cost, 1e-9
  end

  def test_cost_defaults_to_zero_for_empty_json
    r = Response.new(:openai, json: '{}')
    assert_equal 0.0, r.cost
  end

  # ---------------------------------------------------------------------------
  # tool_calls
  # ---------------------------------------------------------------------------

  def test_tool_calls_returns_empty_when_nil
    r = Response.new(:openai, json: openai_json(tool_calls: nil))
    assert_equal [], r.tool_calls
  end

  def test_tool_calls_returns_list_when_present
    calls = [{ 'id' => 'call_1', 'function' => { 'name' => 'search', 'arguments' => '{}' } }]
    r = Response.new(:openai, json: openai_json(tool_calls: calls))
    assert_equal 1, r.tool_calls.length
    assert_equal 'search', r.tool_calls.first.dig('function', 'name')
  end

  # ---------------------------------------------------------------------------
  # to_json round-trip
  # ---------------------------------------------------------------------------

  def test_to_json_round_trips_data
    original = { 'choices' => [{ 'message' => { 'content' => 'hi', 'tool_calls' => nil } }],
                 'usage' => { 'prompt_tokens' => 1, 'completion_tokens' => 1, 'total_tokens' => 2 } }
    r = Response.new(:openai, json: original.to_json)
    assert_equal original, JSON.parse(r.to_json)
  end
end
