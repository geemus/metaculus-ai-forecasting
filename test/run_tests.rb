# frozen_string_literal: true

# Single entry point to run all tests. Usage: bundle exec ruby test/run_tests.rb

require_relative 'test_helper'
require_relative 'test_aggregation'
require_relative 'test_calculator'
require_relative 'test_continuous_cdf'
require_relative 'test_metaculus'
require_relative 'test_prompts'
require_relative 'test_retro_summary'
require_relative 'test_comment_builder'
require_relative 'test_prompt_version'
require_relative 'test_coverage'
require_relative 'test_utility'
require_relative 'test_response_helpers'
require_relative 'test_response'
require_relative 'test_provider'
