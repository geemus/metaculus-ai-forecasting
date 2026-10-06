# frozen_string_literal: true

require_relative 'test_helper'

class TestPrompts < Minitest::Test
  def build_question(type:, scaling: {}, options: nil, units: nil)
    Metaculus::Question.new(data: {
      'created_at' => '2025-01-01T00:00:00Z',
      'question' => {
        'type' => type,
        'scaling' => scaling,
        'options' => options,
        'unit' => units
      }
    })
  end

  # ─── feasibility_check_prompt: bound enumeration ────────────────────────────

  def test_binary_lists_probability_range
    prompt = feasibility_check_prompt(build_question(type: 'binary'))
    assert_includes prompt, 'Probability range: 0%–100%'
  end

  def test_numeric_closed_bounds_marked_closed
    q = build_question(
      type: 'numeric',
      scaling: { 'range_min' => 0, 'range_max' => 100,
                 'open_lower_bound' => false, 'open_upper_bound' => false },
      units: 'votes'
    )
    prompt = feasibility_check_prompt(q)
    assert_includes prompt, 'Lower bound: 0 votes (closed'
    assert_includes prompt, 'Upper bound: 100 votes (closed'
  end

  def test_numeric_open_bounds_marked_open
    q = build_question(
      type: 'numeric',
      scaling: { 'range_min' => 0, 'range_max' => 100,
                 'open_lower_bound' => true, 'open_upper_bound' => true }
    )
    prompt = feasibility_check_prompt(q)
    assert_includes prompt, 'Lower bound: 0 (open'
    assert_includes prompt, 'Upper bound: 100 (open'
  end

  def test_discrete_bounds_are_listed
    q = build_question(type: 'discrete', scaling: { 'nominal_min' => 0, 'nominal_max' => 10 })
    prompt = feasibility_check_prompt(q)
    assert_includes prompt, 'Lower bound: 0'
    assert_includes prompt, 'Upper bound: 10'
  end

  def test_numeric_without_scaling_falls_back_to_generic_line
    prompt = feasibility_check_prompt(build_question(type: 'numeric'))
    assert_includes prompt, 'No question-specific bounds were supplied'
  end

  def test_multiple_choice_lists_sum_constraint_and_options
    prompt = feasibility_check_prompt(build_question(type: 'multiple_choice', options: %w[A B C]))
    assert_includes prompt, 'must sum to 100%'
    assert_includes prompt, 'Options: A, B, C.'
  end

  def test_prompt_requires_structured_block
    prompt = feasibility_check_prompt(build_question(type: 'binary'))
    assert_includes prompt, '<feasibility_check>'
    assert_includes prompt, '</feasibility_check>'
    assert_includes prompt, 'Verdict: SATISFIED | VIOLATION'
    refute_includes prompt, '{{BOUNDS}}'
  end

  # ─── integration: both builders append the check ────────────────────────────

  def test_forecast_prompt_includes_feasibility_check
    @research_output = 'research summary'
    prompt = prompt_with_type(nil, build_question(type: 'binary'), SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, 'Hard Bounds Check'
    assert_includes prompt, '<feasibility_check>'
  end

  def test_consensus_prompt_includes_feasibility_check
    @research_output = 'research summary'
    @revised_forecasts = []
    @mechanical_baseline = nil
    q = build_question(type: 'numeric', scaling: { 'range_min' => 0, 'range_max' => 100 })
    prompt = consensus_prompt_with_type(nil, q, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
    assert_includes prompt, 'Hard Bounds Check'
    assert_includes prompt, '<feasibility_check>'
  end

  # ─── numeric baseline guidance: scale-relative, no fixed threshold ─────────

  def test_numeric_prompt_requires_latest_observed_value_and_date
    assert_includes NUMERIC_FORECAST_PROMPT, 'latest observed value'
    assert_includes NUMERIC_FORECAST_PROMPT, 'as-of date'
  end

  def test_numeric_prompt_requires_stated_deviation_and_direction
    assert_includes NUMERIC_FORECAST_PROMPT, 'as a percentage and in which direction'
  end

  def test_numeric_prompt_judges_deviation_against_quantity_scale
    assert_includes NUMERIC_FORECAST_PROMPT, "the quantity's own scale"
    assert_includes NUMERIC_FORECAST_PROMPT, 'recent movement and its cadence'
  end

  def test_numeric_prompt_requires_direction_matched_catalyst
    assert_includes NUMERIC_FORECAST_PROMPT, 'dated catalyst'
    assert_includes NUMERIC_FORECAST_PROMPT, 'pull your P50 back toward the baseline'
  end

  # A hard percentage here would be anchored on and would collapse the
  # scale-relative judgement into a pass/fail, so the prompt deliberately
  # carries no numeric cut-off.
  def test_numeric_prompt_states_no_fixed_deviation_threshold
    refute_match(/\b\d+(\.\d+)?\s*%/, NUMERIC_FORECAST_PROMPT)
    refute_match(/more than\s*\d/i, NUMERIC_FORECAST_PROMPT)
  end

  def test_forecast_prompt_carries_numeric_baseline_guidance
    @research_output = 'research summary'
    q = build_question(type: 'numeric', scaling: { 'range_min' => 0, 'range_max' => 100 })
    prompt = prompt_with_type(nil, q, SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, 'latest observed value'
    assert_includes prompt, 'dated catalyst'
  end

  def test_consensus_prompt_carries_numeric_baseline_guidance
    @research_output = 'research summary'
    @revised_forecasts = []
    @mechanical_baseline = nil
    q = build_question(type: 'numeric', scaling: { 'range_min' => 0, 'range_max' => 100 })
    prompt = consensus_prompt_with_type(nil, q, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
    assert_includes prompt, 'latest observed value'
    assert_includes prompt, 'dated catalyst'
  end

  # ─── binary base rate vs status quo ────────────────────────────────────────

  def test_superforecaster_prompt_keeps_base_rate_floor
    assert_includes SUPERFORECASTER_SYSTEM_PROMPT, 'even when the current state is "no."'
    assert_includes SUPERFORECASTER_SYSTEM_PROMPT, 'never, by itself, a reason to forecast below it'
  end

  def test_shared_prompt_quantifies_status_quo_prior_as_base_rate
    @research_output = 'research summary'
    prompt = prompt_with_type(nil, build_question(type: 'binary'), SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, 'Express that "no change" prior as a number'
    assert_includes prompt, 'do not substitute a bare "no."'
    assert_includes prompt, '"no is the default" is not such evidence'
  end

  def test_situation_snapshot_separates_base_rate_from_status_quo
    @research_output = 'research summary'
    prompt = prompt_with_type(nil, build_question(type: 'binary'), SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, 'never collapse the base rate to the status-quo outcome'
  end

  # ─── research provenance: retrieval timestamp ──────────────────────────────

  def test_with_research_meta_stamps_retrieval_time
    stamped = with_research_meta("### 1. Base Rate\nbody", at: Time.parse('2026-10-05T14:12:03Z'))
    assert stamped.start_with?("<research_meta>\nresearched_at: 2026-10-05T14:12:03Z\n</research_meta>"), stamped[0, 120]
    assert stamped.end_with?("### 1. Base Rate\nbody")
  end

  def test_research_meta_survives_into_forecaster_prompt
    @research_output = with_research_meta('brief body', at: Time.parse('2026-10-05T14:12:03Z'))
    prompt = prompt_with_type(nil, build_question(type: 'binary'), SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, '<research_meta>'
    assert_includes prompt, 'researched_at: 2026-10-05T14:12:03Z'
  end

  def test_forecaster_prompt_weighs_stale_indicators
    @research_output = 'brief body'
    prompt = prompt_with_type(nil, build_question(type: 'binary'), SHARED_FORECAST_PROMPT_TEMPLATE)
    assert_includes prompt, 'weaker evidence than one observed recently'
  end

  def test_research_prompt_requires_dated_trend
    @forecast_prompt = 'forecast context'
    @news_output = 'news'
    prompt = RESEARCH_PROMPT_TEMPLATE.result(binding)
    assert_includes prompt, 'second, earlier dated observation'
    assert_includes prompt, 'undetermined'
    assert_includes prompt, 'as-of dates and direction'
  end
end
