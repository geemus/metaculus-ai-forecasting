# frozen_string_literal: true

# Pool multiple forecasters' estimates into a single calibrated aggregate.
# Binary and multiple-choice use log-odds / log-probability pooling with an
# extremization factor (Satopää et al. 2014). Numeric percentiles are pooled by
# averaging the inverse CDF at each quantile.
module Aggregation
  EPSILON = 1.0e-6
  DEFAULT_EXTREMIZATION_FACTOR = 1.0

  module_function

  def extremization_factor
    Float(ENV['EXTREMIZATION_FACTOR'] || DEFAULT_EXTREMIZATION_FACTOR)
  end

  # Pool binary probabilities: sigmoid(a * mean(logit(p_i))).
  # a == 1 reduces to the geometric mean of odds; a > 1 extremizes away from 0.5.
  def pool_binary(probs, a: extremization_factor)
    raise ArgumentError, 'probs must not be empty' if probs.empty?

    logits = probs.map { |p| logit(clamp(p)) }
    mean_logit = logits.sum / logits.length.to_f
    sigmoid(a * mean_logit)
  end

  # Pool multiple-choice probability hashes: softmax_k(a * mean_i(log p_i[k])).
  # Preserves sum-to-1 by construction.
  def pool_multiple_choice(prob_dicts, a: extremization_factor)
    raise ArgumentError, 'prob_dicts must not be empty' if prob_dicts.empty?

    keys = prob_dicts.first.keys
    n = prob_dicts.length.to_f
    scaled = keys.map do |k|
      mean_log = prob_dicts.sum { |d| Math.log(clamp(d.fetch(k))) } / n
      [k, a * mean_log]
    end
    softmax(scaled)
  end

  # Quantile-average percentile arrays: at each percentile, take the mean
  # across forecasters. Equivalent to averaging the inverse CDFs.
  def pool_numeric(percentile_arrays)
    raise ArgumentError, 'percentile_arrays must not be empty' if percentile_arrays.empty?

    n = percentile_arrays.length.to_f
    length = percentile_arrays.first.length
    unless percentile_arrays.all? { |a| a.length == length }
      raise ArgumentError, 'all percentile arrays must be the same length'
    end
    Array.new(length) do |i|
      percentile_arrays.sum { |arr| arr[i] } / n
    end
  end

  def clamp(p)
    p.clamp(EPSILON, 1.0 - EPSILON)
  end

  def logit(p)
    Math.log(p / (1.0 - p))
  end

  def sigmoid(x)
    1.0 / (1.0 + Math.exp(-x))
  end

  def softmax(key_value_pairs)
    max = key_value_pairs.map { |_, v| v }.max
    exps = key_value_pairs.map { |k, v| [k, Math.exp(v - max)] }
    total = exps.sum { |_, v| v }
    exps.to_h { |k, v| [k, v / total] }
  end
end
