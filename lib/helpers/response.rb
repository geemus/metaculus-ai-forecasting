# frozen_string_literal: true

require_relative '../aggregation'
require_relative '../prompt_version'

module ResponseHelpers
  def extracted_content(*tags)
    extract_xml(content, *tags).last
  end

  EXPECTED_PERCENTILE_KEYS = [5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95].freeze

  def percentiles
    @percentiles ||= begin
      percentiles = {}
      extracted_content('percentiles').split("\n").each do |line|
        line = line.strip
        next if line.empty?

        key, value = line.split(': ', 2)
        key = key.split('Percentile ', 2).last
        value = value.split(' ', 2).first
        value.gsub!(',', '')
        percentiles[key.to_i] = value.to_f
      end

      missing = EXPECTED_PERCENTILE_KEYS - percentiles.keys
      warn "WARNING: missing percentiles #{missing}" unless missing.empty?

      sorted_pairs = percentiles.sort_by { |k, _| k }
      sorted_values = sorted_pairs.map { |_, v| v }
      unless sorted_values == sorted_values.sort
        warn "WARNING: percentile values are not monotonically increasing: #{percentiles.inspect}"
        # Enforce monotonicity by clamping each value to be at least the previous
        enforced = sorted_values.each_with_object([]) do |v, acc|
          acc << (acc.empty? ? v : [v, acc.last].max)
        end
        if enforced != sorted_values
          percentiles = sorted_pairs.map { |k, _| k }.zip(enforced).to_h
          warn "WARNING: enforced monotonic percentiles: #{percentiles.inspect}"
        end
      end

      percentiles
    end
  end

  def probabilities
    @probabilities ||= begin
      probabilities = {}
      extracted_content('probabilities').split("\n").each do |line|
        line = line.strip
        next if line.empty?

        key, value = line.rpartition(': ').values_at(0, 2)
        probabilities[key.strip] = parse_probability(value)
      end
      probabilities
    end
  end

  def probability
    @probability ||= begin
      probability = parse_probability(extracted_content('probability'))
      clamped = probability.clamp(Aggregation::EPSILON, 1.0 - Aggregation::EPSILON)
      warn "WARNING: probability #{probability} clamped to #{clamped}" if clamped != probability
      clamped
    end
  end

  # Parse a probability string that may be written as "45%", "45", or "0.45".
  # A bare number greater than 1 is treated as a percentage so the model
  # forgetting the % sign doesn't get clamped to 99.9%.
  def parse_probability(text)
    value = text.to_f
    value /= 100.0 if text.include?('%') || value > 1.0
    value
  end

  def calibration_disclaimer
    @calibration_disclaimer ||= extracted_content('calibration_disclaimer')
  end

  def stripped_content(*tags)
    strip_xml(content, *tags)
  end

  # Prompt version this response was generated under (nil for responses
  # cached before stamping was added).
  def prompt_version
    data['prompt_version']
  end

  # Record the current prompt version on a freshly generated response,
  # before it is cached.
  def stamp_prompt_version!
    data.merge!(PromptVersion.stamp)
    self
  end

  def to_json(*)
    data.to_json(*)
  end
end
