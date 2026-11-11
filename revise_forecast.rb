#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')
provider = ARGV[1]&.to_sym || raise('provider name argv[1] is required')

raise ArgumentError, "Unknown forecaster: #{provider}. Expected one of: #{Provider::FORECASTERS.join(', ')}" unless Provider::FORECASTERS.include?(provider)

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

@research_output = load_research(post_id, strip_tags: 'research_summary')
@forecasts = load_forecasts(post_id, type: 'forecast')
@mechanical_baseline = mechanical_baseline(question, @forecasts)

@forecast = @forecasts.find { |f| f.provider == provider }

Formatador.display "\n[bold][green]# Superforecaster[#{provider}]: Revising Forecast(#{post_id})…[/] "
cache(post_id, "forecasts/revision.#{provider}.json") do
  llm_args = { system: SUPERFORECASTER_SYSTEM_PROMPT, temperature: 0.5, tools: [CALCULATOR_TOOL] }
  llm = Provider.new(provider, **llm_args)
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  forecast_delphi_prompt = FORECAST_DELPHI_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, "inputs/revision.#{provider}.md", forecast_delphi_prompt)
  revision = llm.eval(
    { role: 'user', content: forecast_prompt },
    { role: 'assistant', content: @forecast.content },
    { role: 'user', content: forecast_delphi_prompt }
  )
  puts revision.content
  cache_write(post_id, "outputs/revision.#{provider}.md", revision.content)

  # Measure anchoring delta: how much did external signals (peers + community + mechanical) shift the blind estimate?
  begin
    FileUtils.mkdir_p(cache_path(post_id, 'forecasts/deltas'))

    delta = case question.type
            when 'binary'
              blind_prob = @forecast.probability
              revision_prob = revision.probability
              (revision_prob - blind_prob).abs
            when 'numeric', 'discrete'
              blind_p50 = @forecast.percentiles[50]
              revision_p50 = revision.percentiles[50]
              norm = question.upper_bound - question.lower_bound
              norm.positive? ? ((revision_p50 - blind_p50).abs / norm) : 0.0
            when 'multiple_choice'
              blind_probs = @forecast.probabilities
              revision_probs = revision.probabilities
              common_keys = blind_probs.keys & revision_probs.keys
              if common_keys.any?
                common_keys.sum { |k| (revision_probs[k] - blind_probs[k]).abs } / common_keys.size.to_f
              else
                0.0
              end
            end

    cache_write(post_id, "forecasts/deltas/blind_vs_revision.#{provider}.txt", delta.round(6).to_s)
  rescue StandardError => e
    warn "WARNING: failed to measure revision anchoring delta: #{e.message}"
  end

  revision.stamp_prompt_version!.to_json
end
