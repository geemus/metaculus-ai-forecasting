# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/run_store'
require_relative '../lib/run_record'

class TestRunStore < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = RunStore.new(root: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_run_key_layout_sorts_by_time
    early = RunStore.run_key(578, recorded_at: Time.utc(2026, 1, 2, 3, 4, 5), run_id: '99-1')
    late = RunStore.run_key(578, recorded_at: Time.utc(2026, 1, 2, 3, 4, 6), run_id: '11-1')
    assert_equal 'runs/578/20260102T030405Z-99-1.json', early
    assert_operator early, :<, late
  end

  def test_put_get_list_round_trip
    @store.put('runs/1/b.json', { 'a' => 1 })
    @store.put('runs/1/a.json', { 'a' => 2 })
    @store.put('runs/2/a.json', { 'a' => 3 })
    assert_equal({ 'a' => 1 }, @store.get('runs/1/b.json'))
    assert_equal %w[runs/1/a.json runs/1/b.json], @store.list('runs/1')
    assert_equal 3, @store.list.size
  end

  def test_records_are_immutable
    @store.put('runs/1/a.json', {})
    assert_raises(ArgumentError) { @store.put('runs/1/a.json', {}) }
  end

  def test_rejects_keys_outside_root
    assert_raises(ArgumentError) { @store.put('../escape.json', {}) }
    assert_raises(ArgumentError) { @store.put('/abs.json', {}) }
  end
end

class TestRunRecord < Minitest::Test
  POST_ID = 'test_run_record'

  def setup
    init_cache(POST_ID)
    @dir = Dir.mktmpdir
    @store = RunStore.new(root: @dir)
  end

  def teardown
    FileUtils.rm_rf("./tmp/#{POST_ID}")
    FileUtils.rm_rf(@dir)
  end

  def response(provider, content, extra = {})
    Response.new(provider, json: { 'choices' => [{ 'message' => { 'content' => content } }] }.merge(extra).to_json)
  end

  def binary(provider, pct, extra = {})
    response(provider, "<probability>\n#{pct}%\n</probability>", extra)
  end

  def binary_question
    Metaculus::Question.new(data: { 'id' => 1, 'question' => { 'id' => 2, 'type' => 'binary', 'title' => 'Will X?' } })
  end

  def build(**)
    RunRecord.build(post_id: POST_ID, question: binary_question, consensus: binary(:deepseek, 40),
                    forecasts: [binary(:openai, 30)], revisions: [binary(:openai, 35)], **)
  end

  def test_records_stages_with_parsed_values_and_raw_data
    record = build
    assert_equal RunRecord::SCHEMA_VERSION, record['schema_version']
    assert_equal 'binary', record['type']
    assert_in_delta 0.30, record.dig('stages', 'forecast', 'openai', 'value')
    assert_in_delta 0.35, record.dig('stages', 'revision', 'openai', 'value')
    assert_in_delta 0.40, record.dig('stages', 'consensus', 'value')
    assert record.dig('stages', 'consensus', 'choices'), 'raw response kept'
  end

  def test_keeps_model_host_and_usage_from_raw_response
    forecast = binary(:openai, 30, 'model' => 'openai/gpt-x', 'provider' => 'OpenAI', 'usage' => { 'cost' => 0.1 })
    record = RunRecord.build(post_id: POST_ID, question: binary_question, consensus: binary(:deepseek, 40),
                             forecasts: [forecast], revisions: [])
    entry = record.dig('stages', 'forecast', 'openai')
    assert_equal 'openai/gpt-x', entry['model']
    assert_equal 'OpenAI', entry['provider']
    assert_in_delta 0.1, entry.dig('usage', 'cost')
  end

  def test_unparseable_value_is_nil_not_an_error
    record = RunRecord.build(post_id: POST_ID, question: binary_question, consensus: response(:deepseek, 'no tags'),
                             forecasts: [], revisions: [])
    assert_nil record.dig('stages', 'consensus', 'value')
  end

  def test_numeric_percentile_keys_are_strings
    question = Metaculus::Question.new(data: { 'question' => { 'type' => 'numeric' } })
    lines = ResponseHelpers::EXPECTED_PERCENTILE_KEYS.map { |p| "Percentile #{p}: #{p * 10}" }.join("\n")
    consensus = response(:deepseek, "<percentiles>\n#{lines}\n</percentiles>")
    record = RunRecord.build(post_id: POST_ID, question: question, consensus: consensus, forecasts: [], revisions: [])
    assert_in_delta 500.0, record.dig('stages', 'consensus', 'value', '50')
  end

  def test_includes_cached_news_research_and_submission
    File.write(cache_path(POST_ID, 'outputs/news_summary.md'), 'news summary')
    File.write(cache_path(POST_ID, 'research.json'), { 'choices' => [] }.to_json)
    File.write(cache_path(POST_ID, 'consensus/forecast.json'), [{ 'probability_yes' => 0.4 }].to_json)
    File.write(cache_path(POST_ID, 'consensus/comment.json'), { 'text' => 'the comment' }.to_json)
    record = build
    assert_equal 'news summary', record.dig('news', 'summary')
    assert_equal({ 'choices' => [] }, record['research'])
    assert_equal [{ 'probability_yes' => 0.4 }], record.dig('submission', 'forecast')
    assert_equal 'the comment', record.dig('submission', 'comment')
  end

  def test_missing_cached_files_are_nil
    record = build
    assert_nil record.dig('news', 'summary')
    assert_nil record['research']
    assert_nil record.dig('submission', 'forecast')
  end

  def test_save_writes_under_post_prefix
    key = RunRecord.save(store: @store, post_id: POST_ID, question: binary_question, consensus: binary(:deepseek, 40),
                         forecasts: [], revisions: [])
    assert_match %r{\Aruns/#{POST_ID}/\d{8}T\d{6}Z-}, key
    assert_equal 'binary', @store.get(key)['type']
  end

  def test_save_never_raises
    broken = Object.new
    def broken.put(*) = raise('disk full')
    key = nil
    _, err = capture_io do
      key = RunRecord.save(store: broken, post_id: POST_ID, question: binary_question,
                           consensus: binary(:deepseek, 40), forecasts: [], revisions: [])
    end
    assert_nil key
    assert_match(/failed to save run record/, err)
  end
end
