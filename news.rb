#!/usr/bin/env ruby
# frozen_string_literal: true

require 'set'
require_relative 'lib/asknews'
require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

CATEGORIES = %w[
  Business
  Climate
  Crime
  Culture
  Entertainment
  Environment
  Finance
  Health
  Military
  Politics
  Science
  Sports
  Technology
  World
].freeze

filter_prompt = ERB.new(<<~FILTER_PROMPT_TEMPLATE, trim_mode: '-').result(binding)
  You are an expert researcher preparing to research this forecast question:

  <question>
  <%= question.title %>
  </question>

  Background:
  <background>
  <%= question.background %>
  </background>

  The news you find will inform a probability forecast. You must surface a balanced picture covering BOTH:
  - Factors that INCREASE the probability of the forecasted outcome
  - Factors that DECREASE the probability (mitigation, resilience, opposing trends)

  Prefer queries about empirical developments, expert assessments, and real-world data over speculative opinion pieces or AI-generated predictions.

  Before responding, show your reasoning inside `<<<<<< think` / `>>>>>>` tags:
  - What are the 2-3 strongest arguments on each side of this question?
  - What types of recent news would update your assessment in either direction?
  - Then synthesize a search query that covers both sides evenly.

  Provide the search query as a comma-separated keyword list inside `<query>...</query>` tags.
  Provide up to 3 relevant categories from [#{CATEGORIES.join(', ')}] inside `<categories>...</categories>` tags.
FILTER_PROMPT_TEMPLATE

Formatador.display "\n[bold][green]# News: Generating Filters[anthropic/claude-haiku-4-5](#{post_id})…[/] "
filters_json = cache(post_id, 'news_filters.json') do
  llm = OpenRouter.new(
    model: 'anthropic/claude-haiku-4.5',
    system: '',
    tools: []
  )
  filters = llm.eval({ 'role': 'user', 'content': filter_prompt })
  puts filters.content
  categories = filters.extracted_content('categories').split(', ')
  categories.select! { |category| CATEGORIES.include?(category) } # ignore category hallucinations
  {
    categories: categories,
    query: filters.extracted_content('query')
  }.to_json
rescue StandardError => e
  puts e
  puts filters.data
end
filters = JSON.parse(filters_json)
query_display = filters['query'] || '(none)'
categories_display = (filters['categories'] || []).join(', ')
categories_display = '(none)' if categories_display.empty?
Formatador.display "[blue]Query: #{query_display}[/] | [blue]Categories: #{categories_display}[/]\n"

Formatador.display "\n[bold][green]# News: Searching(#{post_id})…[/] "
news_path = cache_path(post_id, 'news.json')
news = if File.exist?(news_path)
         JSON.parse(File.read(news_path))
       else
         AskNews.new.search_news(filters)
       end

# On AskNews failure, write no news artifacts so the next run retries the
# search instead of a blank result being cached (in tmp/ and in CI) forever.
# Downstream stages treat missing news as "no news" (see load_cached_news).
if news.nil?
  Formatador.display_line "\n[yellow]# News: unavailable, skipping(#{post_id})[/]"
  exit
end
cache_write(post_id, 'news.json', news.to_json)

# Filter out low-credibility sources
BLOCKLISTED_DOMAINS = %w[
  ren.tv tsargrad.tv epochtimes.com
].freeze
all_articles = news['as_dicts'].reject do |a|
  source_url = a['source_url'] || ''
  BLOCKLISTED_DOMAINS.any? { |domain| source_url.include?(domain) }
end

# Remove truncated articles (summary cut off by the API)
all_articles.reject! { |a| (a['summary'] || '').include?('[truncated:') }

# Deduplicate near-identical articles from the same source
articles = []
seen = Set.new
all_articles.each do |a|
  title = (a['eng_title'] || '').downcase.gsub(/[^a-z0-9\s]/, '')
  source_id = a['source_id'] || ''
  key = "#{source_id}::#{title[0..80]}"
  unless seen.include?(key)
    seen.add(key)
    articles << a
  end
end
articles = articles[0...10]

news_prompt = ERB.new(<<~NEWS_PROMPT_TEMPLATE, trim_mode: '-')
  Forecast Related News:
  <articles>
  <%- articles.each do |article| -%>
  <article>
  Title: <%= article['eng_title'] %>
  Source: [<%= article['source_id'] %>](<%= article['article_url'] %>)
  Publish Date: <%= article['pub_date'] %>
  Summary: <%= article['summary'] %>
  </article>
  <%- end -%>
  </articles>
NEWS_PROMPT_TEMPLATE

news_md = news_prompt.result(binding)
cache_write(post_id, 'outputs/news.md', news_md)
puts news_md

Formatador.display "\n[bold][green]# News: Summarizing(#{post_id})…[/] "
news_summary = cache(post_id, 'outputs/news_summary.md') do
  llm = OpenRouter.new(
    model: 'anthropic/claude-haiku-4.5',
    system: 'You are a research assistant summarizing news for a forecasting pipeline. Be concise and factual.',
    tools: []
  )
  summary_prompt = <<~PROMPT
    Summarize these news articles into a brief roundup. Include:
    - Article count and date range
    - 3 key themes or developments across the articles
    - The 2-3 most relevant articles for the forecast question (with titles)

    #{news_md}

    Format your response as:
    <news_summary>
    [Your summary here — 4-6 sentences total]
    </news_summary>
  PROMPT
  summary = llm.eval({ role: 'user', content: summary_prompt })
  summary_text = summary.extracted_content('news_summary')

  # Log search metadata for debugging (not included in cached output)
  query = filters['query']
  cats = (filters['categories'] || []).join(', ')
  if (query && !query.empty?) || (cats && !cats.empty?)
    Formatador.display "[blue]Search query: \"#{query}\" | Categories: #{cats}[/]\n"
  end

  summary_text
end
puts news_summary
