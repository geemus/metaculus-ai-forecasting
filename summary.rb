#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argv[0] is required')

fetch_question(post_id)
# exit if should_skip_forecast?(question, post_id)

# cache_write(post_id, 'inputs/system.superforecaster.md', SUPERFORECASTER_SYSTEM_PROMPT)
@research_output = load_research(post_id)

provider = :deepseek
Formatador.display "\n[bold][green]# Summary[#{provider}]: #{post_id}…[/] "
llm = Provider.new(
  :deepseek,
  system: ''
)
prompt = <<~PROMPT
  1. Before responding, show step-by-step reasoning in clear, logical order starting with `<think>` on the line before and ending with `</think>` on the line after.
  2. Review the content within the `<source>` and `</source>` tags below and then provide a short, one sentence summary starting with `<summary>` on the line before and ending with `</summary>` on the line after.

  <source>
  #{@research_output}
  </source>
PROMPT
puts prompt
response = llm.eval({ role: 'user', content: prompt })
puts '---'
puts response.content
exit
