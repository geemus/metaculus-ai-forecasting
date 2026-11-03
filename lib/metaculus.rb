# frozen_string_literal: true

require 'excon'
require 'formatador'
require 'json'
require 'time'

class Metaculus
  def self.get_post(id)
    new.get_post(id)
  end

  def get_post(id)
    start_time = Time.now
    excon_response = with_retry { connection.get(path: "/api/posts/#{id}/") }
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    Question.new(data: JSON.parse(excon_response.body))
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def self.list_tournament_questions(tournament_id)
    new.list_tournament_questions(tournament_id)
  end

  def list_tournament_questions(tournament_id)
    excon_response = with_retry do
      connection.get(
        path: '/api/posts/',
        query: {
          forecast_type: %w[binary discrete multiple_choice numeric].join(','),
          not_forecaster_id: ENV['METACULUS_BOT_ID'],
          include_description: true,
          offset: 0,
          statuses: 'open',
          tournaments: [tournament_id]
        }
      )
    end
    data = JSON.parse(excon_response.body)
    questions = data['results'].map { |datum| Question.new(data: datum) }
    questions.reject! { |question| question.data['status'] == 'closed' }
    questions
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def self.get_comments(post_id)
    new.get_comments(post_id)
  end

  def get_comments(post_id)
    excon_response = with_retry do
      connection.get(
        path: '/api2/comments/',
        query: {
          question: post_id,
          author: ENV['METACULUS_BOT_ID']
        }
      )
    end
    JSON.parse(excon_response.body)
  rescue Excon::Error => e
    puts e.response.inspect
    []
  end

  def self.get_question_with_posts(id)
    new.get_question_with_posts(id)
  end

  def get_question_with_posts(id)
    excon_response = with_retry do
      connection.get(
        path: "/api2/questions/#{id}/",
        query: { include: 'posts' }
      )
    end
    JSON.parse(excon_response.body)
  rescue Excon::Error => e
    puts e.response.inspect
    nil
  end

  def self.list_resolved_tournament_questions(tournament_id)
    new.list_resolved_tournament_questions(tournament_id)
  end

  def list_resolved_tournament_questions(tournament_id)
    excon_response = with_retry do
      connection.get(
        path: '/api/posts/',
        query: {
          forecast_type: %w[binary discrete multiple_choice numeric].join(','),
          forecaster_id: ENV['METACULUS_BOT_ID'],
          include_description: true,
          limit: 100,
          statuses: 'resolved',
          tournaments: [tournament_id],
          with_cp: true
        }
      )
    end
    data = JSON.parse(excon_response.body)
    questions = data['results'].map { |datum| Question.new(data: datum) }
    questions.reject! { |question| question.data['status'] == 'closed' }
    questions
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def post_comment(data)
    Formatador.display_line "\n[bold][green]# Metaculus: Submitting Comment…[/] "
    body = data.to_json
    puts body
    with_retry do
      connection.post(
        path: '/api/comments/create/',
        body: data.to_json,
        expects: 201
      )
    end
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def post_forecasts(data)
    Formatador.display_line "\n[bold][green]# Metaculus: Submitting Forecast…[/] "
    body = data.to_json
    puts body
    with_retry do
      connection.post(
        path: '/api/questions/forecast/',
        body: body,
        expects: 201
      )
    end
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  private

  def connection
    @connection ||= Excon.new(
      'https://www.metaculus.com',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Token #{ENV['METACULUS_BOT_API_TOKEN']}",
        'content-type': 'application/json'
      }
    )
  end

  def with_retry(max_retries: 3, &block)
    retries = 0
    begin
      block.call
    rescue Excon::Error::TooManyRequests => e
      retries += 1
      if retries <= max_retries
        retry_after = e.response&.headers&.dig('Retry-After')&.to_i || 5
        Formatador.display_line(
          "[yellow]# Metaculus: Rate-limited (429), waiting #{retry_after}s (retry #{retries}/#{max_retries})...[/]"
        )
        sleep(retry_after)
        retry
      end
      raise
    end
  end

  class Question
    attr_accessor :data

    def initialize(data:)
      @data = data
    end

    def aggregate_content
      @aggregate_content ||= begin
        return '' unless latest_aggregations

        content = []
        content << "Forecaster Count: #{latest_forecaster_count}"
        if type == 'multiple_choice'
          medians = {}
          options.each_with_index do |option, index|
            medians[option] = latest_aggregations['centers'][index] * 100
          end
          content << "Medians: { #{medians.map { |k,v| format('"%s": %0.2f%%', k, v) }.join(', ')} }"
        else
          units_string = units.empty? ? '' : " #{units}"
          if %w[discrete numeric].include?(type) && scaling['open_lower_bound']
            below_lower_bound = (1 - latest_aggregations['forecast_values'].first) * 100
            content << format(
              'Below %<lower_bound>d: %<below_lower_bound>0.2f%%',
              below_lower_bound: below_lower_bound,
              lower_bound: lower_bound
            )
          end
          lower_bound_val = latest_aggregations['interval_lower_bounds']&.first
          if type != 'binary' && lower_bound_val && upper_bound
            content << "Lower 25%: #{(lower_bound_val * upper_bound).round(2)}#{units_string}"
          end
          content << "Median: #{latest_median}#{units_string}" if latest_median
          upper_bound_val = latest_aggregations['interval_upper_bounds']&.first
          if type != 'binary' && upper_bound_val && upper_bound
            content << "Upper 75%: #{(upper_bound_val * upper_bound).round(2)}#{units_string}"
          end
          if %w[discrete numeric].include?(type) && scaling['open_upper_bound']
            above_upper_bound = (1 - latest_aggregations['forecast_values'].last) * 100
            content << format(
              'Above %<upper_bound>d: %<above_upper_bound>0.2f%%',
              above_upper_bound: above_upper_bound,
              upper_bound: upper_bound
            )
          end
        end
        content.join("\n")
      end
    end

    def background
      @background ||= question && question['description']
    end

    def criteria_content
      @criteria_content ||= [question['resolution_criteria'], question['fine_print']].compact.join("\n\n").strip
    end

    def existing_forecast?
      @existing_forecast ||= !question.dig('my_forecasts', 'latest').nil?
    end

    def id
      @id ||= question['id']
    end

    def latest_forecaster_count
      @latest_forecaster_count ||= latest_aggregations['forecaster_count']
    end

    def latest_median
      @latest_median ||= case type
                         when 'binary'
                           format('%0.2f%%', latest_aggregations['centers'].first * 100)
                         when 'multiple_choice'
                           # handled in aggregate_content
                         else
                           (lower_bound + latest_aggregations['centers'].first * (upper_bound - lower_bound)).round(2)
                         end
    end

    def continuous_cdf(percentiles)
      x_values = cdf_xaxis
      y_values = []

      data = percentiles.dup

      # adjust any values exactly at bounds
      range_size = (upper_bound - lower_bound).abs
      buffer = range_size > 100 ? 1 : 0.01 * range_size
      data.each do |key, value|
        if !scaling['open_lower_bound'] && value <= lower_bound + buffer
          data[key] = lower_bound + buffer
        end
        if !scaling['open_upper_bound'] && value >= upper_bound - buffer
          data[key] = upper_bound - buffer
        end
      end

      # set cdf values outside of range
      if scaling['open_lower_bound']
        data[0.01 * data.keys.min] = lower_bound if lower_bound < data[data.keys.min]
      else
        data[0.0] = lower_bound
      end
      if scaling['open_upper_bound']
        data[99.9] = upper_bound if upper_bound > data[data.keys.max]
      else
        data[100.0] = upper_bound
      end

      # normalize percentiles
      normalized_percentiles = {}
      data.each do |key, value|
        normalized_percentiles[key.to_f / 100] = value
      end

      # swap to map specific values to probabilities
      data = normalized_percentiles.invert
      known_x = data.keys.sort

      x_values.each do |x|
        if known_x.include?(x)
          y_values.append(data[x])
        elsif x < known_x.first
          y_values.append(data[known_x.first])
        elsif x > known_x.last
          y_values.append(data[known_x.last])
        else
          previous_x = known_x.first
          next_x = known_x.last
          known_x.each do |kx|
            next_x = kx
            break if next_x > x

            previous_x = kx
          end
          previous_y = data[previous_x]
          next_y = data[next_x]

          y = previous_y + (x - previous_x) * (next_y - previous_y) / (next_x - previous_x)
          y_values.append(y)
        end
      end

      # standardize - see: https://www.metaculus.com/api/
      # - no mass outside closed bounds (scaling accordingly)
      # - at least minimum amount of mass outside open bounds
      # - increasing by at least minimum amount (0.01 / 200 = 0.0005)
      scale_lower_to = scaling['open_lower_bound'] ? 0.0 : y_values.first
      scale_upper_to = scaling['open_upper_bound'] ? 1.0 : y_values.last
      rescaled_inbound_mass = scale_upper_to - scale_lower_to

      y_values.each_with_index do |y, i|
        location = i / (y_values.length - 1)
        rescaled = (y - scale_lower_to) / rescaled_inbound_mass
        y_value = if scaling['open_lower_bound'] && scaling['open_upper_bound']
                    0.988 * rescaled + 0.01 * location + 0.001
                  elsif scaling['open_lower_bound']
                    0.989 * rescaled + 0.01 * location + 0.001
                  elsif scaling['open_upper_bound']
                    0.989 * rescaled + 0.01 * location
                  else
                    0.99 * rescaled + 0.01 * location
                  end
        # round to avoid floating point errors
        y_values[i] = y_value.round(10)
      end

      # Cap PMF to prevent spiky CDFs: max probability mass per step is 0.2
      # (matches Metaculus template: 0.2 * DEFAULT_INBOUND_OUTCOME_COUNT / cdf_size)
      # Use 0.95 wiggle room factor as in the reference implementation.
      # Iterate until no step exceeds the cap because renormalization can push
      # previously-capped values back above the limit.
      cap = 0.2 * 200.0 / (y_values.length - 1) * 0.95
      total_mass = y_values.each_cons(2).sum { |a, b| b - a }

      loop do
        pmf = y_values.each_cons(2).map { |a, b| b - a }
        break unless pmf.any? { |v| v > cap + 1e-9 }

        capped = pmf.map { |v| [v, cap].min }
        # Renormalize so total mass equals the original span
        capped_mass = capped.sum
        break if capped_mass <= 0

        capped.map! { |v| (v * total_mass / capped_mass).round(10) }
        # Rebuild CDF starting from the original first value
        cumulative = y_values.first
        y_values = [cumulative] + capped.map { |v| (cumulative += v).round(10) }
      end

      y_values
    end

    def lower_bound
      @lower_bound ||= scaling['nominal_min'] || scaling['range_min']
    end

    def resolve_time
      ts = question['scheduled_resolve_time'] || question['actual_resolve_time']
      ts && Time.parse(ts)
    end

    def placeholder_resolve?
      rt = resolve_time
      rt && rt.year >= 2099
    end

    def time_until_resolve
      rt = resolve_time
      return nil unless rt
      return 'Already resolved' if rt <= Time.now
      return 'No fixed resolution date' if placeholder_resolve?

      days = ((rt - Time.now) / 86_400).floor
      parts = ["#{days} day#{'s' unless days == 1}"]
      years = (days / 365.25).round(1)
      parts << "(≈ #{years} year#{'s' if years != 1})" if years >= 0.5
      parts.join(' ')
    end

    def close_time
      ts = question['scheduled_close_time'] || question['actual_close_time']
      ts && Time.parse(ts)
    end

    def time_until_close
      ct = close_time
      return nil unless ct
      return 'Already closed' if ct <= Time.now
      days = ((ct - Time.now) / 86_400).floor
      "#{days} day#{'s' unless days == 1}"
    end

    def metadata_content
      @metadata_content ||= begin
        content = []
        content << "Current Date: #{Time.now.strftime('%B %d, %Y')}"
        asked_on = Time.parse(data['created_at'])
        content << "Asked On: #{asked_on.strftime('%B %d, %Y')}"

        # Resolution date and time remaining
        if (rt = resolve_time)
          if placeholder_resolve?
            content << "Scheduled Resolution: No fixed resolution date"
          elsif rt <= Time.now
            content << "Scheduled Resolution: #{rt.strftime('%B %d, %Y')} (Already resolved)"
          else
            content << "Scheduled Resolution: #{rt.strftime('%B %d, %Y')} (#{time_until_resolve})"
          end
        end

        # Close date
        if (ct = close_time)
          if ct <= Time.now
            content << "Forecasting Closes: #{ct.strftime('%B %d, %Y')} (Already closed)"
          else
            content << "Forecasting Closes: #{ct.strftime('%B %d, %Y')} (#{time_until_close})"
          end
        end

        unless lower_bound.nil?
          content << if scaling['open_lower_bound']
                       "Nominal Lower Bound: #{lower_bound}"
                     else
                       "Lower Bound: #{lower_bound}"
                     end
        end
        content << "Units: #{units}" unless units.nil? || units.empty?
        unless upper_bound.nil?
          content << if scaling['open_upper_bound']
                       "Nominal Upper Bound: #{upper_bound}"
                     else
                       "Upper Bound: #{upper_bound}"
                     end
        end
        content.join("\n")
      end
    end

    def options
      @options ||= question['options']
    end

    def post_id
      @post_id ||= data['id']
    end

    def spot_peer_score
      @spot_peer_score ||= question.dig('my_forecasts', 'score_data', 'spot_peer_score')
    end

    def resolution
      raw = question['resolution']
      return 'Unresolved' if raw.nil?

      case type
      when 'binary'
        case raw
        when 0.0, 0 then 'No'
        when 1.0, 1 then 'Yes'
        when -1 then 'Ambiguous'
        else raw.to_s
        end
      when 'numeric'
        raw.to_s
      when 'discrete'
        if options
          label = if raw.is_a?(Integer)
                    options[raw]
                  else
                    # raw may be a string label; find it in the array
                    idx = options.index(raw)
                    idx ? options[idx] : raw.to_s
                  end
          label ? "#{raw} (#{label})" : raw.to_s
        else
          raw.to_s
        end
      when 'multiple_choice'
        if options
          if raw.is_a?(Integer)
            options[raw] || raw.to_s
          else
            # raw may be a string label; find it in the array
            idx = options.index(raw)
            idx ? options[idx] : raw.to_s
          end
        else
          raw.to_s
        end
      else
        raw.to_s
      end
    end

    def my_prediction
      values = my_forecast_values
      return 'No forecast' unless values

      case type
      when 'binary'
        "#{(values[1] * 100).round(1)}% Yes"
      when 'numeric', 'discrete'
        return "CDF array (#{values.length} points)" unless cdf_xaxis && !cdf_xaxis.empty?

        "#{format_value(cdf_quantile(values, 0.5))} (P50)"
      when 'multiple_choice'
        labels = options || values.each_index.map { |i| "opt #{i}" }
        labels.zip(values).map { |opt, prob| "#{opt}: #{(prob * 100).round(1)}%" }.join(', ')
      else
        values.inspect
      end
    end

    # A retro-facing summary of how the submitted forecast compares with the
    # outcome. The direction label is computed from the outcome, and numeric
    # summaries describe the whole distribution (P10/P50/P90 plus where the
    # resolution fell in it), since peer score depends on more than the P50.
    def error_summary
      return 'Not yet resolved' if question['resolution'].nil?

      values = my_forecast_values
      return 'No forecast to compare' unless values

      case type
      when 'binary' then binary_error_summary(values)
      when 'numeric', 'discrete' then continuous_error_summary(values)
      when 'multiple_choice' then multiple_choice_error_summary(values)
      else 'Unknown question type'
      end
    end

    # Value at quantile q of a submitted CDF. continuous_range is already in
    # question units (and log-spaced for log-scaled questions), so the value is
    # read straight off it, interpolating between grid points.
    def cdf_quantile(cdf, q)
      xs = cdf_xaxis
      idx = cdf.index { |v| v >= q }
      return xs.last if idx.nil?
      return xs[idx] if idx.zero? || cdf[idx] == cdf[idx - 1]

      frac = (q - cdf[idx - 1]) / (cdf[idx] - cdf[idx - 1])
      xs[idx - 1] + frac * (xs[idx] - xs[idx - 1])
    end

    # Forecast CDF evaluated at x (the forecast percentile the outcome landed on).
    def cdf_at(cdf, x)
      xs = cdf_xaxis
      return cdf.first if x <= xs.first
      return cdf.last if x >= xs.last

      idx = xs.index { |v| v >= x }
      frac = (x - xs[idx - 1]) / (xs[idx] - xs[idx - 1])
      cdf[idx - 1] + frac * (cdf[idx] - cdf[idx - 1])
    end

    def my_comment
      # Try local cache first
      comment_path = "./tmp/#{post_id}/consensus/comment.json"
      if File.exist?(comment_path)
        comment_data = JSON.parse(File.read(comment_path))
        return comment_data['text'] if comment_data['text']
      end

      # Try API endpoint that embeds posts in question detail
      question_data = Metaculus.get_question_with_posts(post_id)
      if question_data
        posts = question_data['posts'] || question_data['included'] || []
        my_post = posts.find { |p| p['author'] && p['author']['id'].to_s == ENV['METACULUS_BOT_ID'].to_s }
        return my_post['content'] if my_post && my_post['content']
      end

      'Comments unavailable (API restricted on this endpoint)'
    rescue StandardError
      'Comments unavailable (API restricted on this endpoint)'
    end

    def submit(response, comment_text: nil)
      forecast_data = case type
                      when 'binary'
                        [{
                          question: id,
                          probability_yes: response.probability
                        }]
                      when 'discrete', 'numeric'
                        [{
                          question: id,
                          continuous_cdf: continuous_cdf(response.percentiles)
                        }]
                      when 'multiple_choice'
                        [{
                          question: id,
                          probability_yes_per_category: response.probabilities
                        }]
                      else
                        raise("NOT IMPLEMENTED: question#submit for #{type} questions")
                      end
      metaculus = Metaculus.new
      metaculus.post_forecasts(forecast_data)
      cache_write(post_id, 'consensus/forecast.json', forecast_data.to_json)
      comment_text ||= response.stripped_content('think')
      comment_data = {
        text: comment_text,
        parent: nil,
        included_forecast: true,
        is_private: true,
        on_post: post_id
      }
      metaculus.post_comment(comment_data)
      cache_write(post_id, 'consensus/comment.json', comment_data.to_json)
    end

    def title
      @title ||= question['title']
    end

    def trend
      historical_data = data.dig('question', 'aggregations', 'recency_weighted', 'history') # || synced_question&.trend
      points = historical_data.map do |datum|
        [
          datum['start_time'] + ((datum['start_time'] + datum['end_time']) / 2), # mid-point
          datum['centers'].first
        ]
      end
      n = points.count
      return 0 if n.between?(0, 1)

      summation_xy = points.map { |x, y| x * y }.sum
      summation_x = points.map { |x, _| x }.sum
      summation_y = points.map { |_, y| y }.sum
      summation_x2 = points.map { |x, _| x**2 }.sum

      (n * summation_xy - summation_x * summation_y) / (n * summation_x2 - summation_x**2).to_f
    end

    def type
      @type ||= question['type']
    end

    def units
      @units ||= question['unit']
    end

    def upper_bound
      @upper_bound ||= scaling['nominal_max'] || scaling['range_max']
    end

    def to_json(*args)
      data.to_json(*args)
    end

    private

    def cdf_xaxis
      @cdf_xaxis ||= scaling['continuous_range']
    end

    def my_forecast_values
      question.dig('my_forecasts', 'latest', 'forecast_values')
    end

    def format_value(value)
      unit_str = units.to_s.empty? ? '' : " #{units}"
      "#{value.round(2)}#{unit_str}"
    end

    def binary_outcome
      case question['resolution'].to_s.downcase
      when 'yes', '1', '1.0' then 1.0
      when 'no', '0', '0.0' then 0.0
      end
    end

    def binary_error_summary(values)
      outcome = binary_outcome
      return "Ambiguous or annulled resolution (#{question['resolution']})" if outcome.nil?

      p_yes = values[1]
      gap = ((outcome - p_yes).abs * 100).round(1)
      resolved = outcome == 1.0 ? 'Yes' : 'No'
      direction = if gap.zero?
                    'exact'
                  elsif p_yes >= 0.5 ? outcome == 1.0 : outcome.zero?
                    "right side, #{gap} pts short of #{resolved}"
                  else
                    "wrong side, #{gap} pts from #{resolved}"
                  end
      format('Forecast %<p>.1f%% Yes, resolved %<r>s: %<d>s; Brier %<b>.3f',
             p: p_yes * 100, r: resolved, d: direction, b: (p_yes - outcome)**2)
    end

    def continuous_error_summary(values)
      return 'Cannot compute error (no scaling range)' unless cdf_xaxis && !cdf_xaxis.empty?

      p10, p50, p90 = [0.1, 0.5, 0.9].map { |q| cdf_quantile(values, q) }
      spread = "P10 #{format_value(p10)} / P50 #{format_value(p50)} / P90 #{format_value(p90)}"
      raw = question['resolution'].to_s
      case raw
      when 'above_upper_bound'
        "Resolved above upper bound; forecast #{spread}; " \
          "#{((1 - values.last) * 100).round(1)}% of mass above the upper bound"
      when 'below_lower_bound'
        "Resolved below lower bound; forecast #{spread}; " \
          "#{(values.first * 100).round(1)}% of mass below the lower bound"
      else
        res = Float(raw, exception: false)
        return "Unparseable resolution (#{raw}); forecast #{spread}" if res.nil?

        pct = (cdf_at(values, res) * 100).round(1)
        error = (res - p50).abs
        rel = p50.zero? ? '' : format(' (%.1f%% of P50)', error / p50.abs * 100)
        inside = res.between?(p10, p90) ? 'inside' : 'outside'
        "Resolved #{format_value(res)}; forecast #{spread}; P50 error #{format_value(error)}#{rel}; " \
          "resolution at forecast percentile #{pct} (#{inside} P10–P90)"
      end
    end

    def multiple_choice_error_summary(values)
      raw = question['resolution']
      idx = raw.is_a?(Integer) ? raw : options&.index(raw.to_s)
      return "Unmatched resolution (#{raw})" if idx.nil? || values[idx].nil?

      assigned = values[idx]
      rank = values.sort.reverse.index(assigned) + 1
      label = options ? options[idx] : "option #{idx}"
      format("Assigned %<a>.1f%% to correct answer '%<l>s' (ranked %<r>d of %<n>d); Brier %<b>.3f",
             a: assigned * 100, l: label, r: rank, n: values.length,
             b: values.each_with_index.sum { |v, i| (v - (i == idx ? 1 : 0))**2 })
    end

    def latest_aggregations
      @latest_aggregations ||= begin
        data.dig('question', 'aggregations', 'recency_weighted', 'latest') || synced_question&.send(:latest_aggregations)
      end
    end

    def question
      @question ||= data['question']
    end

    def scaling
      @scaling ||= data.dig('question', 'scaling')
    end

    def synced_question
      @synced_question ||= begin
        return nil unless synced_question_id

        init_cache(synced_question_id)
        post_json = cache(synced_question_id, 'post.json') do
          Metaculus.get_post(synced_question_id).to_json
        end
        Metaculus::Question.new(data: JSON.parse(post_json))
      end
    end

    def synced_question_id
      @synced_question_id ||= begin
        return nil unless background

        json = background.split("\n").last[1...-1]
        data = JSON.parse(json)

        # synced aggregates confuses forecasts about community prediction movement
        return nil if data.dig('info', 'last_cp')

        data.dig('info', 'post_id')
      rescue JSON::ParserError
        nil
      end
    end
  end
end
