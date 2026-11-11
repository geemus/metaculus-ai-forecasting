# frozen_string_literal: true

require 'time'

# Tournament coverage: how many closed questions the bot actually forecast.
# Missed questions usually mean the pipeline never ran while they were open
# (e.g. GitHub skipping scheduled runs), so they're grouped by close date to
# make outage windows visible.
module Coverage
  WARN_BELOW = 0.9

  Result = Struct.new(:total, :covered, :missed, keyword_init: true) do
    def ratio
      total.zero? ? 1.0 : covered.to_f / total
    end

    def percent
      (ratio * 100).round
    end

    def low?
      ratio < WARN_BELOW
    end

    # { 'YYYY-MM-DD' => [post ids...] } by UTC close date, oldest first
    def missed_by_day
      missed.group_by { |p| p[:close_time]&.utc&.strftime('%Y-%m-%d') || 'unknown' }
            .sort.to_h
            .transform_values { |ps| ps.map { |p| p[:id] }.sort }
    end
  end

  # all_posts: raw post hashes from the API; covered_ids: post ids the bot forecast.
  def self.compute(all_posts, covered_ids)
    covered = covered_ids.to_set
    posts = all_posts.map do |post|
      close = post['scheduled_close_time'] || post.dig('question', 'scheduled_close_time')
      { id: post['id'], close_time: close && Time.parse(close) }
    end
    posts = posts.uniq { |p| p[:id] }
    missed = posts.reject { |p| covered.include?(p[:id]) }
    Result.new(total: posts.length, covered: posts.length - missed.length, missed: missed)
  end

  def self.report(result, tournament_id)
    color = result.low? ? 'red' : 'green'
    lines = ["\n[bold][#{color}]# Coverage(#{tournament_id}): " \
             "#{result.covered}/#{result.total} closed questions forecast (#{result.percent}%)[/]"]
    lines << "[red]Below #{(WARN_BELOW * 100).round}% — check that scheduled runs are firing.[/]" if result.low?
    result.missed_by_day.each do |day, ids|
      lines << "  missed #{day}: #{ids.length} — #{ids.join(', ')}"
    end
    lines.join("\n")
  end
end
