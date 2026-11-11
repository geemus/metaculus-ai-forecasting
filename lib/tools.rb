# frozen_string_literal: true

require_relative 'calculator'

CALCULATOR_TOOL = {
  type: 'function',
  function: {
    name: 'calculate',
    description: <<~DESCRIPTION,
      Evaluate an arithmetic expression safely and return the result.

      # Usage
      - Use for any computation with more than two numbers or more than one operation.
      - Use for percentage math, compounding, expected values, Bayes updates.
      - Use when precision matters (e.g. normalization, log-odds conversion).
      - Prefer a single expression; chain via multiple calls if needed.

      # Supported
      - Operators: +, -, *, /, ^ (exponentiation), % (modulo)
      - Functions: SQRT, LOG, LOG10, LOG2, EXP, ABS, ROUND(n), ROUNDDOWN, ROUNDUP
      - Constants: PI, E
      - Grouping: parentheses
      - Functions are case-insensitive (round, ROUND, Round all work).

      # Examples
      - "0.35 * 0.8 + 0.65 * 0.2"
      - "LOG(0.5 / 0.5)"
      - "100 * (1.02 ^ 5)"
      - "SQRT(0.3 * 0.7 / 100)"
      - "ROUND(42.6789, 2)"
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        expression: {
          type: 'string',
          description: 'The arithmetic expression to evaluate (e.g. "0.35 * 0.8 + 0.65 * 0.2").'
        }
      },
      required: ['expression']
    }
  }
}.freeze

module Tools
  class << self
    def calculate(arguments)
      expression = arguments['expression']
      result = Calculator.evaluate(expression)
      result.to_s
    end

    # Shared tool-call dispatch.  Used by all tool-capable clients
    # (OpenRouter, DeepSeek) so that tool routing stays in one place.
    def dispatch(tool_call)
      arguments = JSON.parse(tool_call.dig('function', 'arguments'))
      tool = tool_call.dig('function', 'name')
      case tool
      when 'calculate'
        calculate(arguments)
      else
        raise "Unknown Tool Requested: `#{tool}`"
      end
    end
  end
end
