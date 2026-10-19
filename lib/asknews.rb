# frozen_string_literal: true

require 'excon'
require 'formatador'
require 'json'
require 'time'

class AskNews
  def self.search_news(params)
    new.search_news(params)
  end

  # Archive search ('news knowledge') plus last-48h search ('latest news'),
  # interleaved so the downstream top-N cut keeps a mix of both. Either half
  # may fail independently; nil only when both do.
  STRATEGIES = ['latest news', 'news knowledge'].freeze

  def search_news(params)
    results = STRATEGIES.map { |strategy| search(params, strategy) }.compact
    return nil if results.empty?

    lists = results.map { |result| result['as_dicts'] || [] }
    { 'as_dicts' => interleave(lists).uniq { |a| a['article_url'] } }
  end

  private

  def search(params, strategy)
    start_time = Time.now
    excon_response = connection.get(
      path: '/v1/news/search',
      query: params.merge(
        {
          diversify_sources: true,
          doc_end_delimiter: '</article>',
          doc_start_delimiter: '<article>',
          entity_guarantee_op: 'OR',
          # historical: false,
          # method: 'nl',
          # n_articles: 4, # seems to be ignored
          return_type: 'dicts',
          strategy: strategy,
          string_guarantee_op: 'OR'
        }
      )
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](%<strategy>s in %<minutes>dm %<seconds>ds)[/]',
        strategy: strategy, minutes: duration / 60, seconds: duration % 60
      )
    )
    JSON.parse(excon_response.body)
  rescue Excon::Error => e
    # Non-fatal: news is optional context, so an AskNews outage or lapsed
    # credit should degrade to "no news" rather than halt the pipeline.
    Formatador.display_line("[yellow]AskNews #{strategy} search failed, continuing without it: #{e.class}[/]")
    puts e.response.inspect if e.respond_to?(:response)
    nil
  end

  def interleave(lists)
    longest = lists.map(&:length).max || 0
    (0...longest).flat_map { |i| lists.filter_map { |list| list[i] } }
  end

  def connection
    @connection ||= Excon.new(
      'https://api.asknews.app',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['ASKNEWS_API_KEY']}",
        'content-type': 'application/json'
      },
      idempotent: true,
      retry_interval: 30
    )
  end

  def get_auto_filter_params(query)
    excon_response = connection.get(
      path: '/v1/chat/autofilter',
      query: {
        query: query
      }
    )
    data = JSON.parse(excon_response.body)
    puts(data['filter_params'].select { |k, _| %w[categories query].include?(k) })
    data['filter_params'].select { |k, _| %w[categories query].include?(k) }
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end
end
