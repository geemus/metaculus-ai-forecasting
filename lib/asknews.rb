# frozen_string_literal: true

require 'excon'
require 'formatador'
require 'json'
require 'time'

class AskNews
  def self.search_news(params)
    new.search_news(params)
  end

  def search_news(params)
    start_time = Time.now
    sleep(10) # wait for (free) rate limit
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
          strategy: 'news knowledge',
          string_guarantee_op: 'OR'
        }
      )
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    JSON.parse(excon_response.body)
  rescue Excon::Error => e
    # Non-fatal: news is optional context, so an AskNews outage or lapsed
    # credit should degrade to "no news" rather than halt the pipeline.
    Formatador.display_line("[yellow]AskNews search failed, continuing without news: #{e.class}[/]")
    puts e.response.inspect if e.respond_to?(:response)
    nil
  end

  private

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
