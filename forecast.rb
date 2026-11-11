#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argv[0] is required')
provider = ARGV[1]&.to_sym || raise('provider name argv[1] is required')

unless Provider::FORECASTERS.include?(provider)
  raise ArgumentError, "Unknown forecaster: #{provider}. Expected one of: #{Provider::FORECASTERS.join(', ')}"
end

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

cache_write(post_id, 'inputs/system.superforecaster.md', SUPERFORECASTER_SYSTEM_PROMPT)
@research_output = load_research(post_id, strip_tags: "research_summary")

Formatador.display "\n[bold][green]# Superforecaster[#{provider}]: Forecasting(#{post_id})…[/] "
cache(post_id, "forecasts/forecast.#{provider}.json") do
  # All forecasters route through function-calling-capable clients.  Web
  # search is centralized upstream in tools_research.rb (research_summary
  # is injected above), so forecasters get only CALCULATOR_TOOL.
  llm_args = { system: SUPERFORECASTER_SYSTEM_PROMPT, temperature: 0.9, tools: [CALCULATOR_TOOL] }
  llm = Provider.new(provider, **llm_args)

  # Blind estimate: no external signals (community aggregate shown later during Delphi revision)
  forecast_prompt_blind = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  cache_write(post_id, "inputs/forecast.#{provider}.blind.md", forecast_prompt_blind)
  blind_response = llm.eval({ 'role': 'user', 'content': forecast_prompt_blind })
  cache_write(post_id, "outputs/forecast.#{provider}.blind.md", blind_response.content)
  puts blind_response.content
  cache_write(post_id, "outputs/forecast.#{provider}.md", blind_response.content)
  blind_response.stamp_prompt_version!.to_json
end
