# frozen_string_literal: true

require './lib/response'
require './lib/tools'

class OpenRouter
  attr_accessor :model, :reasoning, :system, :temperature, :tools

  def initialize(
    api_key: ENV['OPEN_ROUTER_API_KEY'],
    model:,
    reasoning: { effort: 'medium' },
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1,
    tools: [CALCULATOR_TOOL]
  )
    @api_key = api_key
    @model = model
    @reasoning = reasoning
    @system = system
    @temperature = temperature
    @tools = tools
  end

  # https://openrouter.ai/docs
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # max_tokens: 2048,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': system
          }
        ].concat(messages),
        reasoning: reasoning,
        temperature: temperature,
        tools: tools,
        usage: { include: true }
      }.to_json
    )
    response = Response.new(
      :open_router,
      duration: Time.now - start_time,
      json: excon_response.body
    )
    messages << {
      'role' => 'assistant',
      'content' => response.content,
      'reasoning_content' => response.reasoning_content
    }
    if response.tool_calls.empty?
      response.display_meta
      response
    else
      messages.last['tool_calls'] = response.tool_calls
      response.tool_calls.each do |tool_call|
        messages << {
          'content' => Tools.dispatch(tool_call),
          'role' => 'tool',
          'tool_call_id' => tool_call['id']
        }
      end

      self.eval(*messages)
    end
  rescue JSON::ParserError
    retries = (retries || 0) + 1
    retry if retries <= 3
    raise
  rescue Excon::Error => e
    puts e.message
    puts e.response.body
    exit(1)
  end

  private

  def connection
    Excon.new(
      'https://openrouter.ai/api/v1/chat/completions',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{@api_key}",
        'content-type': 'application/json'
      },
      idempotent: true,
      read_timeout: 600
    )
  end
end
