# frozen_string_literal: true

require_relative 'test_helper'

class TestContinuousCdf < Minitest::Test
  # Build a minimal Question object with the given scaling configuration.
  # continuous_range is 201 evenly-spaced Float values from range_min to range_max,
  # mirroring real Metaculus API JSON which delivers all numeric values as Floats.
  def build_question(range_min:, range_max:, open_lower: false, open_upper: false, size: 201)
    rmin = range_min.to_f
    rmax = range_max.to_f
    continuous_range = Array.new(size) { |i| rmin + i * (rmax - rmin) / (size - 1) }
    Metaculus::Question.new(data: {
      'question' => {
        'scaling' => {
          'range_min' => rmin,
          'range_max' => rmax,
          'open_lower_bound' => open_lower,
          'open_upper_bound' => open_upper,
          'continuous_range' => continuous_range
        }
      }
    })
  end

  # Wide percentiles spread across most of the 0-10000 range (all Float values).
  def wide_percentiles
    { 5 => 500.0, 10 => 1000.0, 20 => 2000.0, 25 => 2500.0, 30 => 3000.0,
      40 => 4000.0, 50 => 5000.0, 60 => 6000.0, 70 => 7000.0, 75 => 7500.0,
      80 => 8000.0, 90 => 9000.0, 95 => 9500.0 }
  end

  # Very tight percentiles: nearly all mass between 990 and 1010 on 0-10000.
  def spiky_percentiles
    { 5 => 990.0, 10 => 992.0, 20 => 994.0, 25 => 995.0, 30 => 996.0,
      40 => 998.0, 45 => 999.0, 50 => 1000.0, 55 => 1001.0,
      60 => 1002.0, 70 => 1004.0, 75 => 1005.0, 80 => 1006.0, 90 => 1008.0, 95 => 1010.0 }
  end

  def max_step(cdf)
    cdf.each_cons(2).map { |a, b| b - a }.max
  end

  def pmf_cap(cdf_size)
    0.2 * 200.0 / (cdf_size - 1) * 0.95
  end

  # ─── Basic structural invariants ────────────────────────────────────────────

  def test_wide_distribution_produces_201_element_cdf
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(wide_percentiles)
    assert_equal 201, cdf.length
  end

  def test_wide_distribution_cdf_is_monotonically_nondecreasing
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(wide_percentiles)
    cdf.each_cons(2) do |a, b|
      assert b >= a, "CDF decreased from #{a} to #{b}"
    end
  end

  def test_wide_distribution_cdf_stays_within_0_1
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(wide_percentiles)
    assert cdf.min >= 0.0, "CDF has values below 0"
    assert cdf.max <= 1.0, "CDF has values above 1"
  end

  # ─── PMF cap: wide (well-spread) distributions ──────────────────────────────

  def test_wide_distribution_not_capped
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(wide_percentiles)
    cap = pmf_cap(cdf.length)
    assert max_step(cdf) <= cap + 1e-6,
           "Wide distribution unexpectedly exceeded cap: max_step=#{max_step(cdf)} cap=#{cap}"
  end

  # ─── PMF cap: spiky (tight) distributions ───────────────────────────────────

  def test_spiky_distribution_is_smoothed
    # Canonical test case from issue #87: P45=999, P50=1000, P55=1001 on 0-10000
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(spiky_percentiles)
    cap = pmf_cap(cdf.length)
    assert max_step(cdf) <= cap + 1e-6,
           "Spiky CDF exceeds cap: max_step=#{max_step(cdf).round(6)} cap=#{cap.round(6)}"
  end

  def test_spiky_distribution_cdf_is_monotonically_nondecreasing_after_capping
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(spiky_percentiles)
    cdf.each_cons(2) do |a, b|
      assert b >= a, "Capped CDF decreased from #{a} to #{b}"
    end
  end

  def test_spiky_distribution_cdf_stays_within_0_1_after_capping
    q = build_question(range_min: 0, range_max: 10_000)
    cdf = q.continuous_cdf(spiky_percentiles)
    assert cdf.min >= 0.0, "Capped CDF has values below 0"
    assert cdf.max <= 1.0, "Capped CDF has values above 1"
  end

  def test_capping_preserves_first_and_last_cdf_values
    q = build_question(range_min: 0, range_max: 10_000)
    cdf_wide  = q.continuous_cdf(wide_percentiles)
    cdf_spiky = q.continuous_cdf(spiky_percentiles)
    # First and last values come from the standardization formula, not the PMF capping,
    # so they should be the same regardless of whether capping fired.
    assert_in_delta cdf_wide.first, cdf_spiky.first, 1e-6,
                    "First CDF value changed after capping"
    assert_in_delta cdf_wide.last, cdf_spiky.last, 1e-6,
                    "Last CDF value changed after capping"
  end

  # ─── Open-bound variants ─────────────────────────────────────────────────────

  def test_spiky_distribution_capped_with_open_lower_bound
    q = build_question(range_min: 0, range_max: 10_000, open_lower: true)
    cdf = q.continuous_cdf(spiky_percentiles)
    cap = pmf_cap(cdf.length)
    assert max_step(cdf) <= cap + 1e-6,
           "Open-lower spiky CDF exceeds cap: max_step=#{max_step(cdf).round(6)}"
  end

  def test_spiky_distribution_capped_with_open_upper_bound
    q = build_question(range_min: 0, range_max: 10_000, open_upper: true)
    cdf = q.continuous_cdf(spiky_percentiles)
    cap = pmf_cap(cdf.length)
    assert max_step(cdf) <= cap + 1e-6,
           "Open-upper spiky CDF exceeds cap: max_step=#{max_step(cdf).round(6)}"
  end

  def test_spiky_distribution_capped_with_both_bounds_open
    q = build_question(range_min: 0, range_max: 10_000, open_lower: true, open_upper: true)
    cdf = q.continuous_cdf(spiky_percentiles)
    cap = pmf_cap(cdf.length)
    assert max_step(cdf) <= cap + 1e-6,
           "Both-open spiky CDF exceeds cap: max_step=#{max_step(cdf).round(6)}"
  end
end
