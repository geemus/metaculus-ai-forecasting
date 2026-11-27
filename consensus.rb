#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

@research_output = load_research(post_id, strip_tags: 'research_summary')
@revised_forecasts = load_forecasts(post_id, type: 'revision')
@mechanical_baseline = mechanical_baseline(question, @revised_forecasts)

retries_remaining = 3

begin
  provider = :deepseek
  Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus(#{post_id})…[/] "
  consensus_json = cache(post_id, 'forecasts/consensus.json') do
    llm = Provider.new(provider, system: CONSENSUS_SYSTEM_PROMPT)
    consensus_prompt = consensus_prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
    cache_write(post_id, 'inputs/consensus.md', consensus_prompt)
    consensus = llm.eval({ role: 'user', content: consensus_prompt })
    cache_write(post_id, 'outputs/consensus.md', consensus.content)
    consensus.stamp_prompt_version!.to_json
  end
  consensus = Response.new(provider, json: consensus_json)
  puts consensus.content

  question.submit(consensus, comment_text: CommentBuilder.build_pipeline_comment(post_id, question, consensus, @revised_forecasts))

  # Durable record of this run for later analysis (CI uploads it to S3).
  original_forecasts = begin
    load_forecasts(post_id, type: 'forecast')
  rescue StandardError => e
    warn "WARNING: original forecasts unavailable for run record: #{e.message}"
    []
  end
  key = RunRecord.save(post_id: post_id, question: question, consensus: consensus,
                       forecasts: original_forecasts, revisions: @revised_forecasts,
                       mechanical_baseline: @mechanical_baseline)
  Formatador.display_line("[green]# Run record: #{key}[/]") if key
rescue StandardError => e
  puts e.message
  puts "! Retries remaining: #{retries_remaining - 1}"
  cache_delete(post_id, 'forecasts/consensus.json')
  retry if (retries_remaining -= 1).positive?
end
