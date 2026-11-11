# frozen_string_literal: true

require_relative 'test_helper'

class TestAggregation < Minitest::Test
  # ─── pool_binary ────────────────────────────────────────────────────────────

  def test_pool_binary_identity_returns_input_value
    [0.05, 0.3, 0.5, 0.7, 0.95].each do |p|
      pooled = Aggregation.pool_binary([p, p, p, p], a: 1.0)
      assert_in_delta p, pooled, 1e-9
    end
  end

  def test_pool_binary_identity_with_default_extremization_is_invariant_at_one_half
    pooled = Aggregation.pool_binary([0.5, 0.5, 0.5])
    assert_in_delta 0.5, pooled, 1e-12
  end

  def test_pool_binary_a_one_matches_geometric_mean_of_odds
    probs = [0.1, 0.3, 0.6, 0.8]
    odds = probs.map { |p| p / (1.0 - p) }
    geom_mean_odds = Math.exp(odds.map { |o| Math.log(o) }.sum / odds.length)
    expected = geom_mean_odds / (1.0 + geom_mean_odds)
    assert_in_delta expected, Aggregation.pool_binary(probs, a: 1.0), 1e-12
  end

  def test_pool_binary_extremization_pushes_away_from_one_half
    probs = [0.6, 0.65, 0.7, 0.75]
    base = Aggregation.pool_binary(probs, a: 1.0)
    extreme = Aggregation.pool_binary(probs, a: 2.0)
    assert extreme > base, "expected a=2 to push above a=1 for >0.5 pool (base=#{base}, extreme=#{extreme})"

    low_probs = probs.map { |p| 1.0 - p }
    base_low = Aggregation.pool_binary(low_probs, a: 1.0)
    extreme_low = Aggregation.pool_binary(low_probs, a: 2.0)
    assert extreme_low < base_low, "expected a=2 to push below a=1 for <0.5 pool"
  end

  def test_pool_binary_clamps_zero_and_one
    pooled_zero = Aggregation.pool_binary([0.0, 0.5], a: 1.0)
    pooled_one = Aggregation.pool_binary([1.0, 0.5], a: 1.0)
    assert pooled_zero.between?(0.0, 1.0), "out of range: #{pooled_zero}"
    assert pooled_one.between?(0.0, 1.0), "out of range: #{pooled_one}"
    refute pooled_zero.nan?
    refute pooled_one.nan?
  end

  def test_pool_binary_raises_on_empty_input
    assert_raises(ArgumentError) { Aggregation.pool_binary([]) }
  end

  # ─── pool_multiple_choice ───────────────────────────────────────────────────

  def test_pool_multiple_choice_sums_to_one
    forecasts = [
      { 'a' => 0.7, 'b' => 0.2, 'c' => 0.1 },
      { 'a' => 0.4, 'b' => 0.4, 'c' => 0.2 },
      { 'a' => 0.5, 'b' => 0.3, 'c' => 0.2 }
    ]
    pooled = Aggregation.pool_multiple_choice(forecasts, a: 1.5)
    assert_in_delta 1.0, pooled.values.sum, 1e-9
  end

  def test_pool_multiple_choice_identity
    forecast = { 'a' => 0.6, 'b' => 0.3, 'c' => 0.1 }
    pooled = Aggregation.pool_multiple_choice([forecast, forecast], a: 1.0)
    forecast.each do |k, v|
      assert_in_delta v, pooled[k], 1e-9
    end
  end

  def test_pool_multiple_choice_handles_zero_probability_option
    forecasts = [
      { 'a' => 0.0, 'b' => 0.5, 'c' => 0.5 },
      { 'a' => 0.4, 'b' => 0.3, 'c' => 0.3 }
    ]
    pooled = Aggregation.pool_multiple_choice(forecasts, a: 1.5)
    assert_in_delta 1.0, pooled.values.sum, 1e-9
    assert pooled['a'] >= 0.0
    refute pooled['a'].nan?
  end

  def test_pool_multiple_choice_extremization_amplifies_leader
    forecasts = [
      { 'a' => 0.5, 'b' => 0.3, 'c' => 0.2 },
      { 'a' => 0.5, 'b' => 0.3, 'c' => 0.2 }
    ]
    base = Aggregation.pool_multiple_choice(forecasts, a: 1.0)
    extreme = Aggregation.pool_multiple_choice(forecasts, a: 2.0)
    assert extreme['a'] > base['a'], 'extremization should amplify the leading option'
    assert extreme['c'] < base['c'], 'extremization should suppress the trailing option'
    assert_in_delta 1.0, extreme.values.sum, 1e-9
  end

  def test_pool_multiple_choice_raises_on_empty_input
    assert_raises(ArgumentError) { Aggregation.pool_multiple_choice([]) }
  end

  # ─── pool_numeric ───────────────────────────────────────────────────────────

  def test_pool_numeric_averages_each_quantile
    a = [10.0, 20.0, 30.0, 40.0, 50.0]
    b = [20.0, 30.0, 40.0, 50.0, 60.0]
    pooled = Aggregation.pool_numeric([a, b])
    assert_equal [15.0, 25.0, 35.0, 45.0, 55.0], pooled
  end

  def test_pool_numeric_preserves_monotonicity
    a = [1.0, 2.0, 5.0, 8.0, 10.0]
    b = [0.5, 3.0, 4.0, 7.0, 12.0]
    c = [2.0, 2.5, 6.0, 9.0, 11.0]
    pooled = Aggregation.pool_numeric([a, b, c])
    pooled.each_cons(2) do |x, y|
      assert y >= x, "pooled CDF decreased: #{pooled.inspect}"
    end
  end

  def test_pool_numeric_identity
    arr = [5.0, 12.0, 20.0]
    pooled = Aggregation.pool_numeric([arr, arr, arr])
    arr.each_with_index do |v, i|
      assert_in_delta v, pooled[i], 1e-9
    end
  end

  def test_pool_numeric_raises_on_empty_input
    assert_raises(ArgumentError) { Aggregation.pool_numeric([]) }
  end

  def test_pool_numeric_raises_on_mismatched_lengths
    assert_raises(ArgumentError) { Aggregation.pool_numeric([[1.0, 2.0, 3.0], [4.0, 5.0]]) }
  end

  # ─── extremization factor ENV override ──────────────────────────────────────

  def test_extremization_factor_defaults_to_one
    ENV.delete('EXTREMIZATION_FACTOR')
    assert_in_delta 1.0, Aggregation.extremization_factor, 1e-12
  end

  def test_extremization_factor_reads_env
    original = ENV['EXTREMIZATION_FACTOR']
    ENV['EXTREMIZATION_FACTOR'] = '2.5'
    assert_in_delta 2.5, Aggregation.extremization_factor, 1e-12
  ensure
    if original.nil?
      ENV.delete('EXTREMIZATION_FACTOR')
    else
      ENV['EXTREMIZATION_FACTOR'] = original
    end
  end
end
