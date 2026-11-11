# frozen_string_literal: true

require_relative 'test_helper'

# Tests for ResponseHelpers via the Response class, which includes the module
# and provides access to the global extract_xml / strip_xml methods.
class ResponseHelpersTest < Minitest::Test
  def make_response(content, provider: :openai)
    json = {
      'choices' => [{ 'message' => { 'content' => content, 'tool_calls' => nil } }],
      'usage'   => { 'prompt_tokens' => 10, 'completion_tokens' => 5, 'total_tokens' => 15 }
    }.to_json
    Response.new(provider, json: json)
  end

  # ---------------------------------------------------------------------------
  # probability
  # ---------------------------------------------------------------------------

  def test_probability_parses_percentage
    r = make_response('<probability>75%</probability>')
    assert_in_delta 0.75, r.probability, 0.0001
  end

  def test_probability_parses_decimal
    r = make_response('<probability>0.42</probability>')
    assert_in_delta 0.42, r.probability, 0.0001
  end

  def test_probability_clamps_100_percent
    r = make_response('<probability>100%</probability>')
    assert_in_delta 1.0 - Aggregation::EPSILON, r.probability, 1e-9
  end

  # A bare number above 1 is read as a percentage (model dropped the % sign).
  def test_probability_bare_number_above_1_is_percentage
    r = make_response('<probability>45</probability>')
    assert_in_delta 0.45, r.probability, 0.0001
  end

  def test_probability_clamps_below_0
    r = make_response('<probability>-0.1</probability>')
    assert_in_delta Aggregation::EPSILON, r.probability, 1e-9
  end

  def test_probability_clamps_zero
    r = make_response('<probability>0%</probability>')
    assert_in_delta Aggregation::EPSILON, r.probability, 1e-9
  end

  def test_probability_uses_last_tag_when_multiple_present
    r = make_response('<probability>30%</probability><probability>60%</probability>')
    assert_in_delta 0.60, r.probability, 0.0001
  end

  # ---------------------------------------------------------------------------
  # percentiles
  # ---------------------------------------------------------------------------

  SAMPLE_PERCENTILE_CONTENT = <<~CONTENT
    <percentiles>
    Percentile 5: 10
    Percentile 10: 20
    Percentile 20: 30
    Percentile 25: 35
    Percentile 30: 40
    Percentile 40: 48
    Percentile 50: 55
    Percentile 60: 62
    Percentile 70: 72
    Percentile 75: 78
    Percentile 80: 83
    Percentile 90: 90
    Percentile 95: 94
    </percentiles>
  CONTENT

  def test_percentiles_parses_all_expected_keys
    r = make_response(SAMPLE_PERCENTILE_CONTENT)
    expected_keys = [5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95]
    assert_equal expected_keys.sort, r.percentiles.keys.sort
  end

  def test_percentiles_parses_values_correctly
    r = make_response(SAMPLE_PERCENTILE_CONTENT)
    assert_in_delta 10.0, r.percentiles[5],  0.001
    assert_in_delta 55.0, r.percentiles[50], 0.001
    assert_in_delta 94.0, r.percentiles[95], 0.001
  end

  def test_percentiles_strips_commas_from_large_numbers
    content = <<~CONTENT
      <percentiles>
      Percentile 5: 1,000
      Percentile 10: 2,000
      Percentile 20: 3,000
      Percentile 25: 4,000
      Percentile 30: 5,000
      Percentile 40: 6,000
      Percentile 50: 7,000
      Percentile 60: 8,000
      Percentile 70: 9,000
      Percentile 75: 10,000
      Percentile 80: 11,000
      Percentile 90: 12,000
      Percentile 95: 13,000
      </percentiles>
    CONTENT
    r = make_response(content)
    assert_in_delta 1000.0, r.percentiles[5],  0.001
    assert_in_delta 7000.0, r.percentiles[50], 0.001
  end

  def test_percentiles_warns_when_keys_missing
    content = "<percentiles>\nPercentile 50: 55\n</percentiles>"
    r = make_response(content)
    _, err = capture_io { r.percentiles }
    assert_match(/missing percentiles/, err)
  end

  def test_percentiles_warns_when_not_monotonically_increasing
    content = <<~CONTENT
      <percentiles>
      Percentile 5: 80
      Percentile 10: 70
      Percentile 20: 60
      Percentile 25: 50
      Percentile 30: 45
      Percentile 40: 40
      Percentile 50: 35
      Percentile 60: 30
      Percentile 70: 25
      Percentile 75: 20
      Percentile 80: 15
      Percentile 90: 10
      Percentile 95: 5
      </percentiles>
    CONTENT
    r = make_response(content)
    _, err = capture_io { r.percentiles }
    assert_match(/not monotonically increasing/, err)
  end

  # ---------------------------------------------------------------------------
  # probabilities
  # ---------------------------------------------------------------------------

  def test_probabilities_parses_percentage_values
    content = <<~CONTENT
      <probabilities>
      Yes: 70%
      No: 30%
      </probabilities>
    CONTENT
    r = make_response(content)
    assert_in_delta 0.70, r.probabilities['Yes'], 0.001
    assert_in_delta 0.30, r.probabilities['No'],  0.001
  end

  def test_probabilities_parses_decimal_values
    content = <<~CONTENT
      <probabilities>
      Yes: 0.6
      No: 0.4
      </probabilities>
    CONTENT
    r = make_response(content)
    assert_in_delta 0.6, r.probabilities['Yes'], 0.001
    assert_in_delta 0.4, r.probabilities['No'],  0.001
  end

  # Keys are kept verbatim so they match question.options exactly; splitting on
  # the last ': ' lets option names themselves contain colons.
  def test_probabilities_keeps_option_names_verbatim
    content = <<~CONTENT
      <probabilities>
      Option A: 50%
      Ratio 2: 1 or higher: 50%
      </probabilities>
    CONTENT
    r = make_response(content)
    assert_equal({ 'Option A' => 0.5, 'Ratio 2: 1 or higher' => 0.5 }, r.probabilities)
  end

  # ---------------------------------------------------------------------------
  # extracted_content / stripped_content
  # ---------------------------------------------------------------------------

  def test_extracted_content_returns_last_match
    r = make_response('<think>reasoning here</think> final answer')
    assert_equal 'reasoning here', r.extracted_content('think')
  end

  def test_stripped_content_removes_tag_and_content
    r = make_response('<think>some reasoning</think>final answer')
    result = r.stripped_content('think')
    refute_includes result, 'some reasoning'
    assert_includes result, 'final answer'
  end
end
