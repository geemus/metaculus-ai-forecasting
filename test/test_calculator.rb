# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/calculator'

class TestCalculator < Minitest::Test
  # ── basic ops ────────────────────────────────────────────────────────────
  def test_basic_addition
    assert_equal 5, Calculator.evaluate('2 + 3')
  end

  def test_basic_subtraction
    assert_equal 1, Calculator.evaluate('4 - 3')
  end

  def test_basic_multiplication
    assert_equal 12, Calculator.evaluate('3 * 4')
  end

  def test_basic_division
    assert_equal 2.5, Calculator.evaluate('5 / 2')
  end

  def test_exponentiation
    assert_equal 8, Calculator.evaluate('2 ^ 3')
  end

  def test_modulo
    assert_equal 1, Calculator.evaluate('10 % 3')
  end

  # ── precedence and grouping ──────────────────────────────────────────────
  def test_operator_precedence
    assert_equal 14, Calculator.evaluate('2 + 3 * 4')
  end

  def test_parentheses
    assert_equal 20, Calculator.evaluate('(2 + 3) * 4')
  end

  def test_nested_parentheses
    assert_equal 25, Calculator.evaluate('((2 + 3) * (3 + 2))')
  end

  # ── math functions ───────────────────────────────────────────────────────
  def test_sqrt
    assert_equal 4, Calculator.evaluate('SQRT(16)')
  end

  def test_log_natural
    assert_in_delta 1.0, Calculator.evaluate('LOG(E)'), 0.001
  end

  def test_log10
    assert_equal 2, Calculator.evaluate('LOG10(100)')
  end

  def test_log2
    assert_equal 3, Calculator.evaluate('LOG2(8)')
  end

  def test_exp
    assert_in_delta 7.389, Calculator.evaluate('EXP(2)'), 0.001
  end

  def test_abs_positive
    assert_equal 5, Calculator.evaluate('ABS(5)')
  end

  def test_abs_negative
    assert_equal 5, Calculator.evaluate('ABS(-5)')
  end

  def test_round_default
    assert_equal 43, Calculator.evaluate('ROUND(42.6789)')
  end

  def test_round_with_precision
    assert_equal 42.68, Calculator.evaluate('ROUND(42.6789, 2)')
  end

  def test_rounddown
    assert_equal 42, Calculator.evaluate('ROUNDDOWN(42.6789)')
  end

  def test_roundup
    assert_equal 43, Calculator.evaluate('ROUNDUP(42.6789)')
  end

  # ── case-insensitive functions ───────────────────────────────────────────
  def test_lowercase_function
    assert_equal 4, Calculator.evaluate('sqrt(16)')
  end

  def test_mixed_case_function
    assert_equal 4, Calculator.evaluate('Sqrt(16)')
  end

  # ── constants ────────────────────────────────────────────────────────────
  def test_pi
    assert_in_delta 3.14159, Calculator.evaluate('PI'), 0.0001
  end

  def test_e
    assert_in_delta 2.71828, Calculator.evaluate('E'), 0.0001
  end

  # ── example expressions from issue #123 ──────────────────────────────────
  def test_expected_value
    assert_equal 0.41, Calculator.evaluate('0.35 * 0.8 + 0.65 * 0.2')
  end

  def test_log_odds
    assert_equal 0.0, Calculator.evaluate('LOG(0.5 / 0.5)')
  end

  def test_compound_growth
    assert_in_delta 110.41, Calculator.evaluate('100 * (1.02 ^ 5)'), 0.01
  end

  def test_standard_error
    assert_in_delta 0.0458, Calculator.evaluate('SQRT(0.3 * 0.7 / 100)'), 0.0001
  end

  def test_round_financial
    assert_equal 42.68, Calculator.evaluate('ROUND(42.6789, 2)')
  end

  # ── edge cases ───────────────────────────────────────────────────────────
  def test_division_by_zero_returns_error_string
    result = Calculator.evaluate('1 / 0')
    assert_match(/error/i, result.to_s)
  end

  def test_malformed_expression_returns_error_string
    result = Calculator.evaluate('2 + + 3')
    assert_match(/error/i, result.to_s)
  end

  def test_empty_string_returns_error_string
    result = Calculator.evaluate('')
    assert_match(/error/i, result.to_s)
  end

  def test_nil_input_returns_error_string
    result = Calculator.evaluate(nil)
    assert_match(/error/i, result.to_s)
  end

  def test_float_precision
    assert_in_delta 0.3333, Calculator.evaluate('1 / 3'), 0.0001
  end

  def test_negative_numbers
    assert_equal(-5, Calculator.evaluate('-2 - 3'))
  end
end
