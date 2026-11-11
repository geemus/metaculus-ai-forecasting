# frozen_string_literal: true

require_relative 'test_helper'

class TestCoverage < Minitest::Test
  def post(id, close)
    { 'id' => id, 'scheduled_close_time' => close }
  end

  def posts
    [
      post(1, '2026-11-02T03:45:11Z'),
      post(2, '2026-11-02T09:00:00Z'),
      post(3, '2026-11-03T01:00:00Z'),
      post(4, '2026-11-03T05:00:00Z')
    ]
  end

  def test_counts_and_percent
    result = Coverage.compute(posts, [2, 4])
    assert_equal 4, result.total
    assert_equal 2, result.covered
    assert_equal 50, result.percent
    assert result.low?
  end

  def test_missed_grouped_by_utc_close_day
    result = Coverage.compute(posts, [2])
    assert_equal({ '2026-11-02' => [1], '2026-11-03' => [3, 4] }, result.missed_by_day)
  end

  def test_full_coverage_not_low
    result = Coverage.compute(posts, [1, 2, 3, 4, 99])
    assert_equal 100, result.percent
    refute result.low?
    assert_empty result.missed
  end

  def test_empty_tournament_is_full_coverage
    result = Coverage.compute([], [])
    assert_equal 100, result.percent
    refute result.low?
  end

  def test_falls_back_to_question_close_time_and_dedupes
    raw = [{ 'id' => 5, 'question' => { 'scheduled_close_time' => '2026-11-04T00:00:00Z' } },
           { 'id' => 5, 'question' => { 'scheduled_close_time' => '2026-11-04T00:00:00Z' } }]
    result = Coverage.compute(raw, [])
    assert_equal 1, result.total
    assert_equal({ '2026-11-04' => [5] }, result.missed_by_day)
  end

  def test_report_flags_low_coverage_and_lists_misses
    report = Coverage.report(Coverage.compute(posts, [2]), 'minibench')
    assert_includes report, '1/4 closed questions forecast (25%)'
    assert_includes report, '[red]'
    assert_includes report, 'missed 2026-11-03: 2 — 3, 4'
  end
end
