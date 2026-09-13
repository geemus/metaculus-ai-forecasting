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
      # For log-scale questions, transform value keys to normalized CDF location space
      # so that interpolation is done in log-space rather than linear value space.
      # For linear-scale questions this is mathematically equivalent to the original.
      data = normalized_percentiles.invert
      data = data.transform_keys { |v| cdf_location(v) } if scaling['zero_point']
      known_x = data.keys.sort

      x_values.each do |x|
        eval_x = scaling['zero_point'] ? cdf_location(x) : x
        if known_x.include?(eval_x)
          y_values.append(data[eval_x])
        elsif eval_x < known_x.first
          y_values.append(data[known_x.first])
        elsif eval_x > known_x.last
          y_values.append(data[known_x.last])
        else
          previous_x = known_x.first
          next_x = known_x.last
          known_x.each do |kx|
            next_x = kx
            break if next_x > eval_x

            previous_x = kx
          end
          previous_y = data[previous_x]
          next_y = data[next_x]

          y = previous_y + (eval_x - previous_x) * (next_y - previous_y) / (next_x - previous_x)
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
      latest = question.dig('my_forecasts', 'latest')
      return 'No forecast' unless latest

      values = latest['forecast_values']
      return 'No forecast values' unless values

      case type
      when 'binary'
        p_yes = (values[1] * 100).round(1)
        "#{p_yes}% Yes"
      when 'numeric', 'discrete'
        cdf = values
        x_axis = scaling['continuous_range']
        if x_axis && !x_axis.empty?
          idx = cdf.index { |v| v >= 0.5 } || (cdf.length - 1)
          x_val = x_axis[idx]
          range = upper_bound - lower_bound
          x_span = x_axis.last - x_axis.first
          actual = if x_span.positive?
                     (lower_bound + x_val * range / x_span).round(2)
                   else
                     x_val.round(2)
                   end
          unit_str = units.empty? ? '' : " #{units}"
          "#{actual}#{unit_str} (P50)"
        else
          # fallback: show first few CDF values
          "CDF array (#{cdf.length} points)"
        end
      when 'multiple_choice'
        if options
          options.zip(values).map do |opt, prob|
            "#{opt}: #{(prob * 100).round(1)}%"
          end.join(', ')
        else
          values.each_with_index.map { |v, i| "opt #{i}: #{(v * 100).round(1)}%" }.join(', ')
        end
      else
        values.inspect
      end
    end

    def error_summary
      res = question['resolution']&.to_f
      return 'Not yet resolved' if res.nil?

      latest = question.dig('my_forecasts', 'latest')
      return 'No forecast to compare' unless latest

      values = latest['forecast_values']
      return 'No forecast values' unless values

      case type
      when 'binary'
        if res == -1
          return 'Ambiguous resolution'
        end

        p_yes = values[1]
        diff = (res - p_yes).abs
        direction = if p_yes > res
                      'overconfident in Yes'
                    elsif p_yes < res
                      'underconfident in Yes'
                    else
                      'perfect'
                    end
        format('Error: %<diff>.1f%% (%<direction>s)', diff: diff * 100, direction: direction)
      when 'numeric', 'discrete'
        cdf = values
        x_axis = scaling['continuous_range']
        if x_axis && !x_axis.empty?
          idx = cdf.index { |v| v >= 0.5 } || (cdf.length - 1)
          p50_x = x_axis[idx]
          range = upper_bound - lower_bound
          x_span = x_axis.last - x_axis.first
          p50 = if x_span.positive?
                  lower_bound + p50_x * range / x_span
                else
                  p50_x
                end
          abs_error = (res.to_f - p50).abs.round(2)
          unit_str = units.empty? ? '' : " #{units}"
          "Absolute error: #{abs_error}#{unit_str} (resolved #{res}, predicted P50 #{p50.round(2)})"
        else
          'Cannot compute error (no scaling range)'
        end
      when 'multiple_choice'
        correct_idx = res.to_i
        prob_assigned = values[correct_idx] || 0
        surprisal = ((1 - prob_assigned) * 100).round(1)
        correct_option = options ? (options[correct_idx] || "option #{correct_idx}") : "option #{correct_idx}"
        "Surprisal: #{surprisal}% (assigned #{(prob_assigned * 100).round(1)}% to correct answer '#{correct_option}')"
      else
        'Unknown question type'
      end
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

    def cdf_location(value)
      min = scaling['range_min'].to_f
      max = scaling['range_max'].to_f
      zero_pt = scaling['zero_point']

      if zero_pt.nil?
        (value - min) / (max - min)
      else
        zero_pt = zero_pt.to_f
        deriv_ratio = (max - zero_pt) / (min - zero_pt)
        safe_value = value == zero_pt ? value + 1e-10 : value.to_f
        (Math.log((safe_value - min) * (deriv_ratio - 1) + (max - min)) - Math.log(max - min)) / Math.log(deriv_ratio)
      end
    end

    def cdf_xaxis
      @cdf_xaxis ||= scaling['continuous_range']
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
