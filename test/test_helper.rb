# frozen_string_literal: true

# SimpleCov must be started before any lib files are loaded.
require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  track_files 'lib/**/*.rb'
  minimum_coverage 0
end

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'time'
require 'erb'
require 'tmpdir'
require 'formatador'

Thread.current[:formatador] = Formatador.new

require_relative '../lib/helpers/response'
require_relative '../lib/utility'
require_relative '../lib/response'
require_relative '../lib/metaculus'
require_relative '../lib/prompts'
require_relative '../lib/tools'
require_relative '../lib/open_router'
require_relative '../lib/provider'
require_relative '../lib/aggregation'
require_relative '../lib/coverage'
