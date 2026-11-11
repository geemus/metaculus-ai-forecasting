#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argument is required')
type = ARGV[1] || raise('type argument is required')

question = load_cached_question(post_id)
@forecasts = load_forecasts(post_id, type: type)

unless question.aggregate_content.empty?
  Formatador.display "\n[bold][green]# Aggregates:[/]\n"
  Formatador.indent do
    question.aggregate_content.split("\n").each { |line| Formatador.display_line(line) }
  end
end

count = @forecasts.count
case question.type
when 'binary'
  values = @forecasts.map(&:probability).map { |p| p.round(10) }
  sorted = values.sort
  pooled = Aggregation.pool_binary(values).round(6)
  Formatador.display "\n[bold][green]# #{type} Stats #{values}: count: #{count}, pooled: #{pooled}, median: #{sorted_median(sorted)}, stddev: #{stddev(values).round(6)}[/]\n"
when 'numeric', 'discrete'
  keys = @forecasts.first.percentiles.keys.sort
  arrays = @forecasts.map { |f| keys.map { |k| f.percentiles[k] } }
  pooled_array = Aggregation.pool_numeric(arrays)
  pooled_p50 = keys.zip(pooled_array).to_h[50]&.round(3)
  values = @forecasts.map { |f| f.percentiles[50] }
  sorted = values.sort
  Formatador.display "\n[bold][green]# #{type} Stats P50 #{values}: count: #{count}, pooled P50: #{pooled_p50}, median: #{sorted_median(sorted)}[/]\n"
when 'multiple_choice'
  probabilities = @forecasts.map(&:probabilities)
  pooled = Aggregation.pool_multiple_choice(probabilities)
  probabilities.first.each_key do |key|
    values = probabilities.map { |fp| fp[key].round(10) }
    sorted = values.sort
    Formatador.display "\n[bold][green]# #{type} Stats `#{key}` = #{values}: count: #{count}, pooled: #{pooled[key].round(6)}, median: #{sorted_median(sorted)}, stddev: #{stddev(values).round(6)}[/]"
  end
  puts
end
