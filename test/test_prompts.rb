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
end
