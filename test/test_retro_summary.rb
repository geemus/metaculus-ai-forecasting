# frozen_string_literal: true

require_relative 'test_helper'

# Retro-facing summaries (my_prediction / error_summary) read the bot's own
# latest forecast off a resolved question.
class TestRetroSummary < Minitest::Test
  def build(type:, resolution:, values:, scaling: nil, options: nil, unit: nil)
    question = {
      'type' => type,
      'resolution' => resolution,
      'unit' => unit,
      'my_forecasts' => { 'latest' => { 'forecast_values' => values } }
    }
    question['scaling'] = scaling if scaling
    question['options'] = options if options
    Metaculus::Question.new(data: { 'question' => question })
  end

  # Linear CDF from range_min..range_max: uniform mass over a non-zero lower bound.
  def uniform_numeric(resolution:, rmin: 60_000.0, rmax: 160_000.0)
    xs = Array.new(201) { |i| rmin + i * (rmax - rmin) / 200 }
    cdf = Array.new(201) { |i| i / 200.0 }
    build(type: 'numeric', resolution: resolution, values: cdf, unit: 'USD',
          scaling: { 'range_min' => rmin, 'range_max' => rmax, 'continuous_range' => xs })
  end

  # ─── numeric ────────────────────────────────────────────────────────────────

  # continuous_range is already in question units; the P50 must not be offset
  # by the lower bound (previously reported 170,000 here).
  def test_p50_is_read_in_question_units_with_nonzero_lower_bound
    q = uniform_numeric(resolution: '110000')
    assert_equal '110000.0 USD (P50)', q.my_prediction
  end

  def test_numeric_summary_reports_spread_and_resolution_percentile
    q = uniform_numeric(resolution: '77200')
    summary = q.error_summary
    assert_includes summary, 'P10 70000.0 USD / P50 110000.0 USD / P90 150000.0 USD'
    assert_includes summary, 'resolution at forecast percentile 17.2'
    assert_includes summary, 'inside P10–P90'
  end

  def test_numeric_summary_handles_out_of_bounds_resolution
    q = uniform_numeric(resolution: 'above_upper_bound')
    assert_match(/Resolved above upper bound/, q.error_summary)
  end

  # ─── binary ─────────────────────────────────────────────────────────────────

  # The API reports binary resolutions as "yes"/"no" strings; a 91% Yes that
  # resolved Yes used to be labelled "overconfident in Yes".
  def test_binary_string_yes_resolution_labels_underconfidence
    q = build(type: 'binary', resolution: 'yes', values: [0.09, 0.91])
    assert_equal 'Forecast 91.0% Yes, resolved Yes: right side, 9.0 pts short of Yes; Brier 0.008',
                 q.error_summary
  end

  def test_binary_wrong_side_no
    q = build(type: 'binary', resolution: 'no', values: [0.17, 0.83])
    assert_equal 'Forecast 83.0% Yes, resolved No: wrong side, 83.0 pts from No; Brier 0.689',
                 q.error_summary
  end

  def test_binary_annulled
    q = build(type: 'binary', resolution: 'annulled', values: [0.5, 0.5])
    assert_match(/Ambiguous or annulled/, q.error_summary)
  end

  # ─── multiple choice ────────────────────────────────────────────────────────

  def test_multiple_choice_matches_string_resolution_to_option
    q = build(type: 'multiple_choice', resolution: 'B', values: [0.6, 0.3, 0.1], options: %w[A B C])
    assert_equal "Assigned 30.0% to correct answer 'B' (ranked 2 of 3); Brier 0.860", q.error_summary
  end

  # ─── comment selection ──────────────────────────────────────────────────────

  def test_latest_comment_text_picks_newest_live_top_level_comment
    comments = [
      { 'text' => 'old run', 'created_at' => '2026-10-18T10:00:00Z', 'parent_id' => nil },
      { 'text' => 'deleted', 'created_at' => '2026-10-21T10:00:00Z', 'is_soft_deleted' => true },
      { 'text' => 'a reply', 'created_at' => '2026-10-22T10:00:00Z', 'parent_id' => 5 },
      { 'text' => 'latest run', 'created_at' => '2026-10-20T22:33:58.619836Z', 'parent_id' => nil }
    ]
    assert_equal 'latest run', Metaculus.latest_comment_text(comments)
  end

  def test_latest_comment_text_nil_when_none
    assert_nil Metaculus.latest_comment_text([])
  end
end
