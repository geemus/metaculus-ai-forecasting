# frozen_string_literal: true

require './lib/helpers/response'

class Response
  include ResponseHelpers

  attr_accessor :data, :duration, :provider

  def initialize(provider, duration: nil, json: '{}')
    @provider = provider.to_sym
    @data = JSON.parse(json)
    @duration = duration
  end

  def display_meta
    Formatador.display_line(
      format(
        "[light_green][#{provider}](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]",
        {
          total: total_tokens,
          input: input_tokens,
          output: output_tokens,
          minutes: duration_minutes,
          seconds: duration_seconds,
          cost: cost
        }
      )
    )
  end

  def content = @content ||= openai_compatible_content

  def reasoning_content = @reasoning_content ||= openai_compatible_reasoning_content

  def tool_calls = @tool_calls ||= openai_compatible_tool_calls

  def cost
    @cost ||= case provider
              when :deepseek
                deepseek_cost
              when :open_router, :anthropic, :openai
                open_router_cost
              else
                0.0
              end
  end

  def input_tokens = @input_tokens ||= data.dig('usage', 'prompt_tokens') || 0

  def output_tokens = @output_tokens ||= data.dig('usage', 'completion_tokens') || 0

  def total_tokens = @total_tokens ||= data.dig('usage', 'total_tokens') || (input_tokens + output_tokens)

  private

  def duration_minutes
    duration ? duration / 60 : 0
  end

  def duration_seconds
    duration ? duration % 60 : 0
  end

  def open_router_cost
    (data.dig('usage', 'cost') || 0) + (data.dig('usage', 'cost_details')&.values&.compact&.sum || 0)
  end

  # OpenAI-compatible content (used by OpenRouter, DeepSeek, OpenAI)
  def openai_compatible_content
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['content'] }.join("\n")
  end

  # OpenAI-compatible reasoning content (used by OpenRouter, DeepSeek, OpenAI)
  def openai_compatible_reasoning_content
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['reasoning_content'] }.join("\n")
  end

  # OpenAI-compatible tool_calls (used by OpenRouter, DeepSeek, OpenAI)
  def openai_compatible_tool_calls
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['tool_calls'] }.flatten.compact
  end

  # DeepSeek-specific methods
  def deepseek_cost
    cost = 0
    cost += (data.dig('usage', 'prompt_cache_hit_tokens') || 0) / 1_000_000.0 * 0.028  # $0.028/MTok
    cost += (data.dig('usage', 'prompt_cache_miss_tokens') || 0) / 1_000_000.0 * 0.28  # $0.28/MTok
    cost += (output_tokens / 1_000_000.0) * 0.42 # $0.42/MTok
    cost.round(2)
  end
end
