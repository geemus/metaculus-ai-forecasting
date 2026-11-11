#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative('lib/provider')

raise('tournament id or post id argument is required') unless ARGV[0]

id = ARGV[0] || raise('post id argument is required')

post_id = if id.to_i.to_s == id
            id
          else
            IO.popen(['./tournament_questions.rb', id], &:read).split(' ').first
          end

if post_id.nil? || post_id.empty?
  puts "#{id}: No open/unanswered questions available."
  exit
end

raise("Invalid post_id: #{post_id.inspect}") unless post_id.to_i.to_s == post_id

system('./news.rb', post_id)
system('./tools_research.rb', post_id)
post_data = JSON.parse(File.read("tmp/#{post_id}/post.json")) rescue {}
puts post_data['title']
puts post_data.dig('question', 'description')
Provider::FORECASTERS.each do |provider|
  fork { system('./forecast.rb', post_id, provider.to_s) }
end
Process.waitall
system('./forecast_stats.rb', post_id, 'forecast')
Provider::FORECASTERS.each do |provider|
  fork { system('./revise_forecast.rb', post_id, provider.to_s) }
end
Process.waitall
system('./forecast_stats.rb', post_id, 'revision')
system('./consensus.rb', post_id)
