# frozen_string_literal: true

require_relative 'test_helper'

class UtilityTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # extract_xml
  # ---------------------------------------------------------------------------

  def test_extract_xml_basic
    assert_equal ['hello'], extract_xml('<tag>hello</tag>', 'tag')
  end

  def test_extract_xml_strips_surrounding_whitespace
    assert_equal ['hello'], extract_xml("<tag>\n  hello\n</tag>", 'tag')
  end

  def test_extract_xml_multiple_matches_same_tag
    assert_equal ['a', 'b'], extract_xml('<tag>a</tag><tag>b</tag>', 'tag')
  end

  def test_extract_xml_multiple_different_tags
    result = extract_xml('<a>first</a><b>second</b>', 'a', 'b')
    assert_equal ['first', 'second'], result
  end

  def test_extract_xml_missing_tag_returns_empty
    assert_equal [], extract_xml('no tags here', 'missing')
  end

  def test_extract_xml_multiline_content
    text = "<reasoning>\nline one\nline two\n</reasoning>"
    result = extract_xml(text, 'reasoning')
    assert_equal 1, result.length
    assert_includes result.first, 'line one'
    assert_includes result.first, 'line two'
  end

  def test_extract_xml_returns_last_of_multiple_when_used_as_extracted_content
    # extract_xml returns all matches; caller takes .last for single-value tags
    results = extract_xml('<p>75%</p><p>80%</p>', 'p')
    assert_equal '80%', results.last
  end

  # ---------------------------------------------------------------------------
  # strip_xml
  # ---------------------------------------------------------------------------

  def test_strip_xml_removes_tag_and_content
    assert_equal 'beforeafter', strip_xml('before<tag>inner</tag>after', 'tag')
  end

  def test_strip_xml_multiple_tags
    result = strip_xml('<a>x</a> between <b>y</b>', 'a', 'b')
    refute_includes result, 'x'
    refute_includes result, 'y'
    assert_includes result, 'between'
  end

  def test_strip_xml_no_match_returns_unchanged
    assert_equal 'no tags here', strip_xml('no tags here', 'missing')
  end

  def test_strip_xml_multiline_content
    text = "preamble\n<think>\nsome reasoning\n</think>\nconclusion"
    result = strip_xml(text, 'think')
    assert_includes result, 'preamble'
    assert_includes result, 'conclusion'
    refute_includes result, 'some reasoning'
  end

  # ---------------------------------------------------------------------------
  # stddev
  # ---------------------------------------------------------------------------

  def test_stddev_empty_returns_zero
    assert_equal 0.0, stddev([])
  end

  def test_stddev_single_value_returns_zero
    assert_equal 0.0, stddev([5.0])
  end

  def test_stddev_known_values
    # Population stddev for [2, 4, 4, 4, 5, 5, 7, 9] = 2.0
    assert_in_delta 2.0, stddev([2, 4, 4, 4, 5, 5, 7, 9]), 0.0001
  end

  def test_stddev_identical_values_returns_zero
    assert_equal 0.0, stddev([7.0, 7.0, 7.0])
  end

  def test_stddev_two_values
    # stddev([0, 10]) = 5.0
    assert_in_delta 5.0, stddev([0, 10]), 0.0001
  end

  # ---------------------------------------------------------------------------
  # sorted_median
  # ---------------------------------------------------------------------------

  def test_sorted_median_empty_returns_nil
    assert_nil sorted_median([])
  end

  def test_sorted_median_single_value
    assert_equal 5.0, sorted_median([5.0])
  end

  def test_sorted_median_odd_count_returns_middle
    assert_equal 3.0, sorted_median([1.0, 3.0, 5.0])
  end

  def test_sorted_median_even_count_returns_average_of_middle_two
    assert_in_delta 3.5, sorted_median([1.0, 2.0, 5.0, 6.0]), 0.001
  end

  def test_sorted_median_two_values
    assert_in_delta 3.0, sorted_median([1.0, 5.0]), 0.001
  end

  # ---------------------------------------------------------------------------
  # TestQuestions
  # ---------------------------------------------------------------------------

  def test_test_question_true_for_string_ids
    assert TestQuestions.test_question?('578')
    assert TestQuestions.test_question?('14333')
    assert TestQuestions.test_question?('22427')
    assert TestQuestions.test_question?('38880')
  end

  def test_test_question_true_for_integer_ids
    assert TestQuestions.test_question?(578)
    assert TestQuestions.test_question?(14333)
    assert TestQuestions.test_question?(22427)
    assert TestQuestions.test_question?(38880)
  end

  def test_test_question_false_for_unknown_id
    refute TestQuestions.test_question?('99999')
    refute TestQuestions.test_question?(1)
  end

  def test_all_includes_all_four_ids
    assert_equal 4, TestQuestions::ALL.length
    assert_includes TestQuestions::ALL, TestQuestions::BINARY
    assert_includes TestQuestions::ALL, TestQuestions::NUMERIC
    assert_includes TestQuestions::ALL, TestQuestions::MULTIPLE_CHOICE
    assert_includes TestQuestions::ALL, TestQuestions::DISCRETE
  end

  # ---------------------------------------------------------------------------
  # cache / cache_write / cache_read! / cache_concat
  # ---------------------------------------------------------------------------

  TEST_POST_ID = 'test_utility_cache'

  def setup
    init_cache(TEST_POST_ID)
  end

  def teardown
    FileUtils.rm_rf("./tmp/#{TEST_POST_ID}")
  end

  def test_cache_miss_calls_block_and_writes_file
    result = cache(TEST_POST_ID, 'outputs/test.txt') { 'computed value' }
    assert_equal 'computed value', result
    assert File.exist?("./tmp/#{TEST_POST_ID}/outputs/test.txt")
  end

  def test_cache_hit_returns_cached_without_calling_block
    cache_write(TEST_POST_ID, 'outputs/test.txt', 'cached value')
    block_called = false
    result = cache(TEST_POST_ID, 'outputs/test.txt') { block_called = true; 'fresh' }
    assert_equal 'cached value', result
    refute block_called
  end

  def test_cache_read_bang_raises_when_file_missing
    assert_raises(RuntimeError) { cache_read!(TEST_POST_ID, 'outputs/nonexistent.txt') }
  end

  def test_cache_read_bang_returns_content_when_present
    cache_write(TEST_POST_ID, 'outputs/exists.txt', 'hello')
    assert_equal 'hello', cache_read!(TEST_POST_ID, 'outputs/exists.txt')
  end

  def test_cache_write_overwrites_existing_content
    cache_write(TEST_POST_ID, 'outputs/file.txt', 'first')
    cache_write(TEST_POST_ID, 'outputs/file.txt', 'second')
    assert_equal 'second', cache_read!(TEST_POST_ID, 'outputs/file.txt')
  end

  def test_cache_concat_creates_file_on_first_call
    cache_concat(TEST_POST_ID, 'outputs/log.txt', 'line1')
    assert File.exist?("./tmp/#{TEST_POST_ID}/outputs/log.txt")
    content = cache_read!(TEST_POST_ID, 'outputs/log.txt')
    assert_includes content, 'line1'
  end

  def test_cache_concat_appends_on_subsequent_calls
    cache_concat(TEST_POST_ID, 'outputs/log.txt', 'line1')
    cache_concat(TEST_POST_ID, 'outputs/log.txt', 'line2')
    content = cache_read!(TEST_POST_ID, 'outputs/log.txt')
    assert_includes content, 'line1'
    assert_includes content, 'line2'
  end

  def test_cache_delete_removes_file
    cache_write(TEST_POST_ID, 'outputs/temp.txt', 'data')
    cache_delete(TEST_POST_ID, 'outputs/temp.txt')
    refute File.exist?("./tmp/#{TEST_POST_ID}/outputs/temp.txt")
  end

  def test_cache_delete_no_error_when_file_missing
    cache_delete(TEST_POST_ID, 'outputs/nonexistent.txt')  # should not raise
  end

  # ---------------------------------------------------------------------------
  # forecast_peer_summary
  # ---------------------------------------------------------------------------

  MockQuestion   = Struct.new(:type)
  BinaryForecast = Struct.new(:probability)
  NumericForecast = Struct.new(:percentiles)
  MCForecast     = Struct.new(:probabilities)

  def test_forecast_peer_summary_binary_includes_own_and_peer_values
    question  = MockQuestion.new('binary')
    forecasts = [BinaryForecast.new(0.7), BinaryForecast.new(0.5), BinaryForecast.new(0.3)]
    own       = forecasts[0]
    result    = forecast_peer_summary(question, forecasts, own)
    assert_includes result, 'Your estimate: 70.0%'
    assert_includes result, 'Peers'
    assert_includes result, 'min:'
    assert_includes result, 'max:'
  end

  def test_forecast_peer_summary_numeric_includes_p50
    question  = MockQuestion.new('numeric')
    forecasts = [
      NumericForecast.new({ 50 => 60.0 }),
      NumericForecast.new({ 50 => 40.0 }),
      NumericForecast.new({ 50 => 55.0 })
    ]
    own    = forecasts[0]
    result = forecast_peer_summary(question, forecasts, own)
    assert_includes result, 'Your P50: 60.0'
    assert_includes result, 'Peers P50'
  end

  def test_forecast_peer_summary_discrete_same_as_numeric
    question  = MockQuestion.new('discrete')
    forecasts = [
      NumericForecast.new({ 50 => 10.0 }),
      NumericForecast.new({ 50 => 8.0 }),
      NumericForecast.new({ 50 => 12.0 })
    ]
    own    = forecasts[0]
    result = forecast_peer_summary(question, forecasts, own)
    assert_includes result, 'Your P50: 10.0'
  end

  def test_forecast_peer_summary_multiple_choice_lists_all_options
    question  = MockQuestion.new('multiple_choice')
    forecasts = [
      MCForecast.new({ 'Yes' => 0.7, 'No' => 0.3 }),
      MCForecast.new({ 'Yes' => 0.5, 'No' => 0.5 }),
      MCForecast.new({ 'Yes' => 0.6, 'No' => 0.4 })
    ]
    own    = forecasts[0]
    result = forecast_peer_summary(question, forecasts, own)
    assert_includes result, 'Yes'
    assert_includes result, 'No'
    assert_includes result, '70.0%'
  end

  def test_forecast_peer_summary_returns_nil_on_error
    question  = MockQuestion.new('binary')
    forecasts = [BinaryForecast.new(0.5)]
    result    = forecast_peer_summary(question, forecasts, nil)
    assert_nil result
  end
end
