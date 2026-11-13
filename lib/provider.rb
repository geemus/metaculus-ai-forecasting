# frozen_string_literal: true

require 'json'

require './lib/open_router'

# Maps provider names (:openai, :gemini, :deepseek, :anthropic) to OpenRouter
# clients and defines the forecaster ensemble.
module Provider
  # Forecaster ensemble. Single source of truth is forecasters.json, which
  # CI also reads directly (see .github/workflows/forecast.yml).
  FORECASTERS_PATH = File.expand_path('../forecasters.json', __dir__)
  FORECASTERS = JSON.parse(File.read(FORECASTERS_PATH)).map(&:to_sym).freeze

  PROVIDERS = %i[anthropic deepseek gemini openai].freeze

  # OpenRouter provider routing for :deepseek. Prefer DeepSeek's own endpoint;
  # fall back to third-party hosts only when they honor every request
  # parameter (tools, reasoning, temperature) and serve near-full precision,
  # so a fallback doesn't silently become a weaker forecaster. The host that
  # served each response is recorded in the pipeline comment.
  # https://openrouter.ai/docs/guides/routing/provider-selection
  DEEPSEEK_ROUTING = {
    order: ['deepseek'],
    allow_fallbacks: true,
    require_parameters: true,
    quantizations: %w[fp8 bf16 fp16 fp32]
  }.freeze

  class << self
    # Factory method to instantiate a provider
    # Usage: Provider.new(:anthropic, **args)
    def new(provider_symbol, **args)
      raise ArgumentError, "Unknown provider: #{provider_symbol}" unless PROVIDERS.include?(provider_symbol)

      case provider_symbol
      when :anthropic
        args[:model] ||= 'anthropic/claude-opus-5.5'
      when :deepseek
        args[:model] ||= 'deepseek/deepseek-v4-pro'
        args[:routing] ||= DEEPSEEK_ROUTING
      # Forecasters use OpenRouter's ~*-latest aliases so the ensemble tracks
      # the frontier without code changes; the resolved model is recorded per
      # forecaster in the pipeline comment (see CommentBuilder).
      when :gemini
        args[:model] ||= '~google/gemini-pro-latest'
      when :openai
        args[:model] ||= '~openai/gpt-sol-latest'
        args[:api_key] ||= ENV['OPEN_ROUTER_OPENAI_API_KEY'] || ENV.fetch('OPEN_ROUTER_API_KEY', nil)
      end

      OpenRouter.new(**args)
    end
  end
end
