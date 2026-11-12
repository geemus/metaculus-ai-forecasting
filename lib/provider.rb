# frozen_string_literal: true

require 'json'

require './lib/deepseek'
require './lib/open_router'

# Maps provider names (:openai, :gemini, :deepseek, :anthropic) to LLM clients
# and defines the forecaster ensemble.
module Provider
  # Forecaster ensemble. Single source of truth is forecasters.json, which
  # CI also reads directly (see .github/workflows/forecast.yml).
  FORECASTERS_PATH = File.expand_path('../forecasters.json', __dir__)
  FORECASTERS = JSON.parse(File.read(FORECASTERS_PATH)).map(&:to_sym).freeze

  # Map provider symbols to their class names
  PROVIDER_CLASSES = {
    anthropic: OpenRouter,
    gemini: OpenRouter,
    deepseek: DeepSeek,
    openai: OpenRouter
  }.freeze

  class << self
    # Factory method to instantiate a provider
    # Usage: Provider.new(:anthropic, **args)
    def new(provider_symbol, **args)
      klass = PROVIDER_CLASSES[provider_symbol]
      raise ArgumentError, "Unknown provider: #{provider_symbol}" unless klass

      case provider_symbol
      when :anthropic
        args[:model] ||= 'anthropic/claude-opus-5.5'
      # Forecasters use OpenRouter's ~*-latest aliases so the ensemble tracks
      # the frontier without code changes; the resolved model is recorded per
      # forecaster in the pipeline comment (see CommentBuilder).
      when :gemini
        args[:model] ||= '~google/gemini-pro-latest'
      when :openai
        args[:model] ||= '~openai/gpt-sol-latest'
        args[:api_key] ||= ENV['OPEN_ROUTER_OPENAI_API_KEY'] || ENV.fetch('OPEN_ROUTER_API_KEY', nil)
      end

      klass.new(**args)
    end
  end
end
