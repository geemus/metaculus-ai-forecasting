# frozen_string_literal: true
# Single entry point to run all tests. Usage: bundle exec ruby test/run_tests.rb

require_relative 'test_helper'
require_relative 'test_aggregation'
require_relative 'test_calculator'
require_relative 'test_continuous_cdf'
require_relative 'test_metaculus'
require_relative 'test_prompts'
