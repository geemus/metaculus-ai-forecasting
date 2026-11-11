# frozen_string_literal: true

require 'dentaku'

module Calculator
  class << self
    def evaluate(expression)
      calculator = Dentaku::Calculator.new
      calculator.store(pi: Math::PI)
      calculator.store(e: Math::E)
      result = calculator.evaluate(expression)
      raise "Could not evaluate: #{expression}" if result.nil?

      result.is_a?(BigDecimal) ? result.to_f : result
    rescue Dentaku::ParseError => e
      "Parse error: #{e.message}"
    rescue StandardError => e
      "Evaluation error: #{e.message}"
    end
  end
end
