# frozen_string_literal: true

require_relative 'test_helper'

class TestMetaculus < Minitest::Test
  # ─── resolve_time ───────────────────────────────────────────────────────────

  def test_resolve_time_from_scheduled
    q = build_question('scheduled_resolve_time' => '2027-12-31T00:00:00Z')
    assert_equal Time.parse('2027-12-31T00:00:00Z'), q.resolve_time
  end

  def test_resolve_time_falls_back_to_actual
    q = build_question('actual_resolve_time' => '2025-01-15T00:00:00Z')
    assert_equal Time.parse('2025-01-15T00:00:00Z'), q.resolve_time
  end

  def test_resolve_time_prefers_scheduled_over_actual
    q = build_question(
      'scheduled_resolve_time' => '2027-12-31T00:00:00Z',
      'actual_resolve_time' => '2025-01-15T00:00:00Z'
    )
    assert_equal Time.parse('2027-12-31T00:00:00Z'), q.resolve_time
  end

  def test_resolve_time_returns_nil_when_no_dates
    q = build_question({})
    assert_nil q.resolve_time
  end

  # ─── placeholder_resolve? ───────────────────────────────────────────────────

  def test_placeholder_resolve_when_year_2099
    q = build_question('scheduled_resolve_time' => '2099-01-01T00:00:00Z')
    assert q.placeholder_resolve?
  end

  def test_placeholder_resolve_when_year_2100
    q = build_question('scheduled_resolve_time' => '2100-01-02T00:00:00Z')
    assert q.placeholder_resolve?
  end

  def test_placeholder_resolve_false_for_normal_date
    q = build_question('scheduled_resolve_time' => '2027-12-31T00:00:00Z')
    refute q.placeholder_resolve?
  end

  def test_placeholder_resolve_false_when_no_resolve_time
    q = build_question({})
    refute q.placeholder_resolve?
  end

  # ─── time_until_resolve ─────────────────────────────────────────────────────

  def test_time_until_resolve_future
    future = (Time.now + (86_400 * 30) + 60) # 30 days + 60s buffer
    q = build_question('scheduled_resolve_time' => future.utc.iso8601)
    assert_match(/\d+ days/, q.time_until_resolve)
    days = q.time_until_resolve.match(/(\d+) days/)[1].to_i
    assert days >= 29, "expected at least 29 days, got #{days}"
  end

  def test_time_until_resolve_includes_years
    future = (Time.now + (86_400 * 500) + 60) # ~1.37 years + buffer
    q = build_question('scheduled_resolve_time' => future.utc.iso8601)
    assert_match(/\d+ days.*≈.*year/, q.time_until_resolve)
  end

  def test_time_until_resolve_one_day_singular
    future = (Time.now + 86_400 + 60) # 1 day + buffer
    q = build_question('scheduled_resolve_time' => future.utc.iso8601)
    assert_match(/1 day\b/, q.time_until_resolve)
  end

  def test_time_until_resolve_already_resolved
    past = Time.now - 86_400
    q = build_question('scheduled_resolve_time' => past.utc.iso8601)
    assert_equal 'Already resolved', q.time_until_resolve
  end

  def test_time_until_resolve_placeholder
    q = build_question('scheduled_resolve_time' => '2100-01-02T00:00:00Z')
    assert_equal 'No fixed resolution date', q.time_until_resolve
  end

  def test_time_until_resolve_nil_when_no_date
    q = build_question({})
    assert_nil q.time_until_resolve
  end

  # ─── close_time ─────────────────────────────────────────────────────────────

  def test_close_time_from_scheduled
    q = build_question('scheduled_close_time' => '2027-12-30T00:00:00Z')
    assert_equal Time.parse('2027-12-30T00:00:00Z'), q.close_time
  end

  def test_close_time_falls_back_to_actual
    q = build_question('actual_close_time' => '2025-01-14T00:00:00Z')
    assert_equal Time.parse('2025-01-14T00:00:00Z'), q.close_time
  end

  def test_close_time_returns_nil_when_no_dates
    q = build_question({})
    assert_nil q.close_time
  end

  # ─── time_until_close ───────────────────────────────────────────────────────

  def test_time_until_close_future
    future = (Time.now + (86_400 * 14) + 60) # 14 days + buffer
    q = build_question('scheduled_close_time' => future.utc.iso8601)
    assert_match(/\d+ days/, q.time_until_close)
    days = q.time_until_close.match(/(\d+) days/)[1].to_i
    assert days >= 13, "expected at least 13 days, got #{days}"
  end

  def test_time_until_close_already_closed
    past = Time.now - 86_400
    q = build_question('scheduled_close_time' => past.utc.iso8601)
    assert_equal 'Already closed', q.time_until_close
  end

  def test_time_until_close_nil_when_no_date
    q = build_question({})
    assert_nil q.time_until_close
  end

  # ─── metadata_content ───────────────────────────────────────────────────────

  def test_metadata_includes_resolution_info
    future = (Time.now + (86_400 * 60) + 60)
    q = build_question(
      'scheduled_resolve_time' => future.utc.iso8601,
      'scheduled_close_time' => (future - 86_400).utc.iso8601,
      'created_at' => '2025-01-01T00:00:00Z',
      'scaling' => { 'range_min' => 0, 'range_max' => 100 }
    )
    metadata = q.metadata_content
    assert_match(/Asked On:/, metadata)
    assert_match(/Scheduled Resolution:.*\(\d+ days\)/, metadata)
    assert_match(/Forecasting Closes:.*\(\d+ days\)/, metadata)
  end

  def test_metadata_placeholder_resolution
    q = build_question(
      'scheduled_resolve_time' => '2100-01-02T00:00:00Z',
      'scheduled_close_time' => '2100-01-01T00:00:00Z',
      'created_at' => '2025-01-01T00:00:00Z',
      'scaling' => { 'range_min' => 0, 'range_max' => 100 }
    )
    metadata = q.metadata_content
    assert_match(/No fixed resolution date/, metadata)
  end

  def test_metadata_already_resolved
    past = Time.now - 86_400
    q = build_question(
      'scheduled_resolve_time' => past.utc.iso8601,
      'scheduled_close_time' => (past - 86_400).utc.iso8601,
      'created_at' => '2025-01-01T00:00:00Z',
      'scaling' => { 'range_min' => 0, 'range_max' => 100 }
    )
    metadata = q.metadata_content
    assert_match(/Already resolved/, metadata)
    assert_match(/Already closed/, metadata)
  end

  def test_metadata_without_resolution_dates
    q = build_question(
      'created_at' => '2025-01-01T00:00:00Z',
      'scaling' => { 'range_min' => 0, 'range_max' => 100 }
    )
    metadata = q.metadata_content
    assert_match(/Asked On:/, metadata)
    refute_match(/Scheduled Resolution/, metadata)
    refute_match(/Forecasting Closes/, metadata)
  end

  # ─── leap-year boundary ─────────────────────────────────────────────────────

  def test_time_until_resolve_across_leap_year
    future = (Time.now + (86_400 * 600) + 60) # ~1.64 years + buffer
    q = build_question('scheduled_resolve_time' => future.utc.iso8601)
    refute_nil q.time_until_resolve
    refute_equal 'No fixed resolution date', q.time_until_resolve
    refute_equal 'Already resolved', q.time_until_resolve
  end

  # ─── zero / negative remaining time ─────────────────────────────────────────

  def test_time_until_resolve_just_now
    # Time exactly now resolves as "Already resolved" due to <= check
    now = Time.now
    q = build_question('scheduled_resolve_time' => now.utc.iso8601)
    assert_equal 'Already resolved', q.time_until_resolve
  end

  private

  def build_question(question_overrides = {})
    data = {
      'question' => question_overrides
    }
    data['created_at'] ||= '2025-01-01T00:00:00Z'
    Metaculus::Question.new(data: data)
  end
end
