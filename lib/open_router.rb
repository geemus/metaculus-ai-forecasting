# frozen_string_literal: true

require './lib/response'

# OpenRouter chat-completions client; serves every provider (see Provider).
class OpenRouter
  attr_accessor :model, :reasoning, :routing, :system, :temperature

  def initialize( # rubocop:disable Metrics/ParameterLists
    model:, api_key: ENV.fetch('OPEN_ROUTER_API_KEY', nil),
    reasoning: { effort: 'medium' },
    routing: nil,
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1
  )
    @api_key = api_key
    @model = model
    @reasoning = reasoning
    @routing = routing
    @system = system
    @temperature = temperature
  end

  # https://openrouter.ai/docs
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(body: request_body(messages).to_json)
    response = Response.new(
      :open_router,
      duration: Time.now - start_time,
      json: excon_response.body
    )
    response.display_meta
    response
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

  def request_body(messages)
    body = {
      # max_tokens: 2048,
      model: model,
      messages: [
        {
          role: 'system',
          content: system
        }
      ].concat(messages),
      reasoning: reasoning,
      temperature: temperature,
      usage: { include: true }
    }
    # https://openrouter.ai/docs/guides/routing/provider-selection
    body[:provider] = routing if routing
    body
  end

  def connection
    Excon.new(
      'https://openrouter.ai/api/v1/chat/completions',
      expects: 200,
      headers: {
        accept: 'application/json',
        authorization: "Bearer #{@api_key}",
        'content-type': 'application/json'
      },
      idempotent: true,
      read_timeout: 600
    )
  end
end
