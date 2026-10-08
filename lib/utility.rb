# frozen_string_literal: true

require 'formatador'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# create cache directories as needed
def init_cache(post_id)
  FileUtils.mkdir_p("./tmp/#{post_id}")
  %w[consensus forecasts inputs outputs].each do |dir|
    FileUtils.mkdir_p("./tmp/#{post_id}/#{dir}")
  end
end

def cache_path(id, path)
  "./tmp/#{id}/#{path}"
end

def cache(post_id, path, &block)
  tmp_path = cache_path(post_id, path)
  if File.exist?(tmp_path)
    File.read(tmp_path)
  else
    data = block.call
    File.write(tmp_path, data)
    data
  end
end

def cache_concat(question_id, path, data)
  tmp_path = cache_path(question_id, path)
  cached = File.read(tmp_path) if File.exist?(tmp_path)
  File.write(tmp_path, [cached, data].compact.join("\n"))
end

def cache_delete(question_id, path)
  tmp_path = cache_path(question_id, path)
  File.delete(tmp_path) if File.exist?(tmp_path)
end

def cache_read!(question_id, path)
  tmp_path = cache_path(question_id, path)
  raise "Cache Not Found: `#{tmp_path}`" unless File.exist?(tmp_path)

  File.read(tmp_path)
end

def cache_write(question_id, path, data)
  File.write(cache_path(question_id, path), data)
end

# https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/util.py
# https://ruby-doc.org/3.4.1/String.html#method-i-match
def extract_xml(text, *tags)
  extracted = []
  tags.each do |tag|
    regex = %r{<#{tag}>([\s\S]*?)</#{tag}>}
    extracted << text.scan(regex).flatten
  end
  extracted.flatten.map(&:strip)
end

def strip_xml(text, *tags)
  stripped = text.dup
  tags.each do |tag|
    regex = %r{<#{tag}>([\s\S]*)</#{tag}>}
    stripped.gsub!(regex, '')&.strip
  end
  stripped.strip
end

def stddev(values)
  return 0.0 if values.empty?

  average = values.sum / values.count.to_f
  deviation_squares = values.map { |v| (v - average) * (v - average) }
  Math.sqrt(deviation_squares.sum / deviation_squares.count)
end

def sorted_median(sorted_values)
  return nil if sorted_values.empty?

  mid = (sorted_values.count - 1) / 2.0
  ((sorted_values[mid.floor] + sorted_values[mid.ceil]) / 2.0).round(3)
end

def mechanical_baseline(question, forecasts)
  case question.type
  when 'binary'
    pooled = Aggregation.pool_binary(forecasts.map(&:probability))
    a = Aggregation.extremization_factor
    if a == 1.0
      "Log-odds mean: #{(pooled * 100).round(1)}%"
    else
      "Log-odds pool (extremization a=#{a}): #{(pooled * 100).round(1)}%"
    end
  when 'multiple_choice'
    pooled = Aggregation.pool_multiple_choice(forecasts.map(&:probabilities))
    lines = pooled.map { |k, v| "  #{k}: #{(v * 100).round(1)}%" }
    a = Aggregation.extremization_factor
    if a == 1.0
      "Softmax-of-log mean:\n#{lines.join("\n")}"
    else
      "Softmax-of-log pool (extremization a=#{a}):\n#{lines.join("\n")}"
    end
  when 'numeric', 'discrete'
    keys = forecasts.first.percentiles.keys.sort
    arrays = forecasts.map { |f| keys.map { |k| f.percentiles[k] } }
    pooled = Aggregation.pool_numeric(arrays)
    lines = keys.zip(pooled).map { |k, v| "  Percentile #{k.to_s.rjust(2)}: #{v.round(3)}" }
    "Quantile average:\n#{lines.join("\n")}"
  end
rescue StandardError => e
  warn "WARNING: failed to build mechanical baseline: #{e.message}"
  nil
end

def forecast_peer_summary(question, forecasts, own_forecast)
  peers = forecasts.reject { |f| f == own_forecast }
  case question.type
  when 'binary'
    peer_values = peers.map { |f| (f.probability * 100).round(1) }.sort
    own_value = "#{(own_forecast.probability * 100).round(1)}%"
    "Your estimate: #{own_value} | Peers — min: #{peer_values.first}%, median: #{sorted_median(peer_values)}%, max: #{peer_values.last}%"
  when 'numeric', 'discrete'
    peer_values = peers.map { |f| f.percentiles[50] }.sort
    own_value = own_forecast.percentiles[50]
    "Your P50: #{own_value} | Peers P50 — min: #{peer_values.first}, median: #{sorted_median(peer_values)}, max: #{peer_values.last}"
  when 'multiple_choice'
    lines = own_forecast.probabilities.keys.map do |key|
      peer_values = peers.map { |f| (f.probabilities[key] * 100).round(1) }.sort
      own_pct = "#{(own_forecast.probabilities[key] * 100).round(1)}%"
      "  #{key}: #{own_pct} | Peers — min: #{peer_values.first}%, median: #{sorted_median(peer_values)}%, max: #{peer_values.last}%"
    end
    "Your estimates vs. peers:\n#{lines.join("\n")}"
  end
rescue StandardError
  nil
end

# Metaculus test question IDs for development/testing
module TestQuestions
  BINARY = '578'
  NUMERIC = '14333'
  MULTIPLE_CHOICE = '22427'
  DISCRETE = '38880'

  ALL = [BINARY, NUMERIC, MULTIPLE_CHOICE, DISCRETE].freeze

  def self.test_question?(post_id)
    ALL.include?(post_id.to_s)
  end
end

# Check if script should skip a question that already has a forecast
def should_skip_forecast?(question, post_id)
  return false if TestQuestions.test_question?(post_id)

  if question.existing_forecast?
    Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
    true
  else
    false
  end
end

# Load a question from cache or fetch from API if not cached
def load_question(post_id, fetch: true)
  init_cache(post_id)

  if fetch
    Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
    post_json = Metaculus.get_post(post_id).to_json
    cache_write(post_id, 'post.json', post_json)
  else
    post_json = cache_read!(post_id, 'post.json')
  end

  Metaculus::Question.new(data: JSON.parse(post_json))
end

# Load cached deepnews
def load_cached_deepnews(post_id)
  cache_read!(post_id, 'outputs/deepnews.md')
end

# Load cached news
# Missing news.md means the news stage was skipped (e.g. AskNews unavailable);
# research proceeds without news rather than failing.
def load_cached_news(post_id)
  path = cache_path(post_id, 'outputs/news.md')
  File.exist?(path) ? File.read(path) : ''
end

# Convenience method: load from cache only
def load_cached_question(post_id)
  load_question(post_id, fetch: false)
end

# Convenience method: fetch and cache (default behavior)
def fetch_question(post_id)
  load_question(post_id, fetch: true)
end

# Load all forecasts of a given type for all forecasters
def load_forecasts(post_id, type: 'forecast', forecasters: Provider::FORECASTERS)
  forecasters.map do |provider|
    forecast_json = cache_read!(post_id, "forecasts/#{type}.#{provider}.json")
    Response.new(provider, json: forecast_json)
  end
end

# Load a single forecast for a specific forecaster
def load_forecast(post_id, provider, type: 'forecast')
  forecast_json = cache_read!(post_id, "forecasts/#{type}.#{provider}.json")
  Response.new(provider, json: forecast_json)
end

# Stamp the research brief with its retrieval time. research.json is cached
# per post and reused by every later run, so without this stamp a brief
# generated weeks ago is indistinguishable from one generated minutes ago.
def with_research_meta(text, at: Time.now)
  stamp = at.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  "<research_meta>\nresearched_at: #{stamp}\n</research_meta>\n\n#{text}"
end

# Load research and optionally extract stripped content
def load_research(post_id, strip_tags: nil)
  research_json = cache_read!(post_id, 'research.json')
  research = Response.new(:open_router, json: research_json)

  if strip_tags
    tags = strip_tags.is_a?(Array) ? strip_tags : [strip_tags]
    research.stripped_content(*tags)
  else
    research.content
  end
end
