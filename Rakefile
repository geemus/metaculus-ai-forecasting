# frozen_string_literal: true

desc 'Run all tests'
task :test do
  sh 'ruby test/run_tests.rb'
end

desc 'Run tests and open HTML coverage report'
task :coverage do
  sh 'ruby test/run_tests.rb'
  sh 'open coverage/index.html 2>/dev/null || xdg-open coverage/index.html'
end

desc 'Run RuboCop'
task :lint do
  sh 'bundle exec rubocop'
end

task default: :test
