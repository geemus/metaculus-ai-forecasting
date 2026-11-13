# frozen_string_literal: true

require './lib/helpers/response'

# A provider-agnostic wrapper around one LLM API response: content, token
# usage, cost and tool calls.
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

  # Every provider routes through OpenRouter, which reports the billed cost.
  def cost = @cost ||= open_router_cost

  # The upstream host OpenRouter routed the request to (e.g. "DeepSeek");
  # distinct from #provider, which is the forecaster slot.
  def host = data['provider']

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

  # usage.cost is what OpenRouter charged. cost_details repeats the upstream
  # charge (as a total and as prompt/completion parts), so it must not be
  # summed in. Only with BYOK is the upstream charge billed separately (to
  # your own provider key), on top of OpenRouter's fee in usage.cost.
  def open_router_cost
    usage = data['usage'] || {}
    cost = usage['cost'] || 0
    cost += usage.dig('cost_details', 'upstream_inference_cost') || 0 if usage['is_byok']
    cost
  end

  # OpenAI-compatible content (used by OpenRouter)
  def openai_compatible_content
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['content'] }.join("\n")
  end

  # OpenAI-compatible reasoning content (used by OpenRouter)
  def openai_compatible_reasoning_content
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['reasoning_content'] }.join("\n")
  end

  # OpenAI-compatible tool_calls (used by OpenRouter)
  def openai_compatible_tool_calls
    choices = data['choices'] or raise "API error (no choices): #{data.inspect}"
    choices.map { |choice| choice['message']['tool_calls'] }.flatten.compact
  end
end
