#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

cache_write(post_id, 'inputs/system.researcher.md', RESEARCHER_SYSTEM_PROMPT)

@news_output = load_cached_news(post_id)

cache(post_id, 'research.json') do
  Formatador.display "\n[bold][green]# Researcher: Researching(#{post_id})…[/] "

  @forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @research_prompt = RESEARCH_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research.md', @research_prompt)

  start_time = Time.now

  begin
    # Perplexity Agent API with native tools (web_search, finance_search,
    # fetch_url). Eliminates the OpenRouter→Perplexity Chat Completions
    # double-hop: the Agent API runs all tools internally and returns the
    # final research report in a single request.
    # Heavy runs (Claude Opus 5 + high reasoning + 15 steps + three tools)
    # can outlast Perplexity's synchronous request window, which aborts the
    # connection mid-run (HTTP 499 "client_disconnected" / ECONNRESET). To
    # survive long runs we submit in background mode and poll the run
    # status, so the work completes server-side independent of the HTTP
    # connection.
    headers = {
      'accept': 'application/json',
      'authorization': "Bearer #{ENV['PERPLEXITY_API_KEY']}",
      'content-type': 'application/json'
    }

    agent = Excon.new(
      'https://api.perplexity.ai',
      expects: [200, 202],
      headers: headers,
      read_timeout: 60
    )

    # Cap how many URLs the fetch_url tool retrieves per invocation to
    # bound latency and keep fetched content from crowding the reasoning
    # context window. Perplexity accepts 1–10; overridable via env.
    max_urls = [[Integer(ENV['PERPLEXITY_MAX_URLS'] || 4), 1].max, 10].min

    agent_tools = [
      { type: 'web_search' },
      { type: 'finance_search' },
      { type: 'fetch_url', max_urls: max_urls }
    ]

    submission = JSON.parse(
      agent.post(path: '/v1/agent', body: {
        model: 'anthropic/claude-opus-5',
        max_output_tokens: 64000,
        max_steps: 15,
        prompt_cache_key: 'high',
        reasoning: { 'effort': 'high' },
        tool_choice: 'auto',
        input: [{ type: 'message', role: 'user', content: @research_prompt }],
        instructions: RESEARCHER_SYSTEM_PROMPT,
        tools: agent_tools,
        background: true
      }.to_json).body
    )

    run_id = submission['id'] ||
      raise("Perplexity background submission missing id: #{submission.inspect}")
    Formatador.display_line "\n# Researcher: background run #{run_id} (#{submission['status']})"

    # Poll the background run to completion. Each poll is a cheap HTTP GET,
    # so a transient network error just retries the poll instead of
    # aborting the whole research phase.
    poll_deadline = Time.now + Integer(ENV['PERPLEXITY_AGENT_TIMEOUT'] || 1800)
    poll_interval = Float(ENV['PERPLEXITY_POLL_INTERVAL'] || 15)
    response = loop do
      if Time.now >= poll_deadline
        raise "Timed out after #{(Time.now - start_time).round}s waiting for Perplexity agent run #{run_id}"
      end

      begin
        response = JSON.parse(agent.get(path: "/v1/agent/#{run_id}").body)
      rescue Excon::Error => e
        warn "Perplexity poll failed (#{e.message}); retrying…"
        sleep poll_interval
        next
      end

      status = response['status']
      break response if %w[completed failed cancelled incomplete].include?(status)

      sleep poll_interval
    end

    status = response['status']
    unless status == 'completed'
      raise "Perplexity agent run #{run_id} ended with status #{status}: #{response['error'].inspect}"
    end

    summary = response['output'].map { |item| item['type'] }.tally
      .map { |type, count| "#{type}×#{count}" }.sort.join(', ')
    Formatador.display_line "\n# Researcher: #{summary}"

    # Extract text content from the Agent API response.
    # Content may be a plain string or an array of {type, text} blocks,
    # depending on whether web search results were included.
    text = response['output']
      .select { |item| item['role'] == 'assistant' }
      .map { |item| item['content'] }
      .flatten
      .map { |c| c.is_a?(Hash) ? c['text'] : c }
      .compact
      .join("\n")

    # Stamp the brief with its retrieval time before it is cached. The
    # cached research is reused by later runs, so this is the only record
    # of how old the brief in hand actually is.
    text = with_research_meta(text)

    cache_write(post_id, 'outputs/research.md', text)

    duration = Time.now - start_time
    Formatador.display_line(
      format(
        "[light_green][perplexity_agent](%<total>d tokens in %<minutes>dm %<seconds>ds)[/]",
        {
          total: response.dig('usage', 'total_tokens') || 0,
          minutes: (duration / 60).to_i,
          seconds: (duration % 60).to_i
        }
      )
    )

    # Transform to OpenAI-compatible shape so downstream consumers
    # (load_research → Response.new(:open_router, …)) parse unchanged.
    openai_compatible = {
      'choices' => [
        {
          'message' => {
            'content' => text,
            'role' => 'assistant'
          },
          'finish_reason' => 'stop'
        }
      ],
      'usage' => {
        'prompt_tokens' => response.dig('usage', 'input_tokens') || 0,
        'completion_tokens' => response.dig('usage', 'output_tokens') || 0,
        'total_tokens' => response.dig('usage', 'total_tokens') || 0
      },
      'model' => response['model'] || 'anthropic/claude-opus-5'
    }

    JSON.pretty_generate(openai_compatible)
  rescue JSON::ParserError
    retries = (retries || 0) + 1
    retry if retries <= 3
    raise
  rescue Excon::Error => e
    puts e.message
    puts e.response&.body
    exit(1)
  end
end
