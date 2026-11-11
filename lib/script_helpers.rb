# frozen_string_literal: true

# Common requires for all scripts
require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require_relative 'provider'
require_relative 'response'
require_relative 'metaculus'
require_relative 'prompts'
require_relative 'prompt_version'
require_relative 'utility'
require_relative 'aggregation'
require_relative 'comment_builder'
require_relative 'coverage'
