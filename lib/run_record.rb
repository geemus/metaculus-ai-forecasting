# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative 'prompt_version'
require_relative 'run_store'

# One self-contained JSON record per submitted forecast: the question as it
# stood at forecast time (including the community aggregate), news, research,
# every stage's raw LLM response, the mechanical baseline, and what was
# submitted. It is written once after a successful submission and never
# edited; resolutions and scores are recorded separately once known.
#
# Raw responses are kept whole (content, model, serving host, usage, cost,
# prompt_version) so later analysis can recompute anything. Each also carries
# a `value` parsed with the pipeline's own parser so readers in other
# languages need not reimplement it.
#
# Bump SCHEMA_VERSION on any change a reader would need to handle; readers
# branch on it rather than old records being rewritten.
module RunRecord
  SCHEMA_VERSION = 1

  module_function

  def build(post_id:, question:, consensus:, forecasts:, revisions:, # rubocop:disable Metrics/ParameterLists
            mechanical_baseline: nil, recorded_at: Time.now)
    {
      'schema_version' => SCHEMA_VERSION,
      'post_id' => post_id.to_s.match?(/\A\d+\z/) ? post_id.to_i : post_id.to_s,
      'question_id' => question.id,
      'title' => question.title,
      'type' => question.type,
      'test_question' => TestQuestions.test_question?(post_id),
      'recorded_at' => recorded_at.utc.iso8601,
      'run' => run_metadata,
      'prompt_version' => PromptVersion::CURRENT,
      'question' => question.data,
      'news' => news(post_id),
      'research' => cached_json(post_id, 'research.json'),
      'stages' => {
        'forecast' => stage(question, forecasts),
        'revision' => stage(question, revisions),
        'consensus' => response_entry(question, consensus)
      },
      'mechanical_baseline' => mechanical_baseline,
      'submission' => {
        'forecast' => cached_json(post_id, 'consensus/forecast.json'),
        'comment' => cached_json(post_id, 'consensus/comment.json')&.fetch('text', nil)
      }
    }
  end

  # Build and store a record, returning its key. Never raises: a failure to
  # record must not fail a forecast that has already been submitted.
  def save(store: RunStore.new, recorded_at: Time.now, **)
    record = build(recorded_at: recorded_at, **)
    key = RunStore.run_key(record['post_id'], recorded_at: recorded_at, run_id: run_id)
    store.put(key, record)
  rescue StandardError => e
    warn "WARNING: failed to save run record: #{e.class}: #{e.message}"
    nil
  end

  # CI runs are identified by run id and attempt (a re-run of the same
  # workflow run is a new attempt); local runs get a random suffix.
  def run_id
    if ENV['GITHUB_RUN_ID']
      "#{ENV['GITHUB_RUN_ID']}-#{ENV.fetch('GITHUB_RUN_ATTEMPT', '1')}"
    else
      "local-#{SecureRandom.hex(4)}"
    end
  end

  def run_metadata
    {
      'repository' => ENV.fetch('GITHUB_REPOSITORY', nil),
      'run_id' => ENV.fetch('GITHUB_RUN_ID', nil),
      'run_attempt' => ENV.fetch('GITHUB_RUN_ATTEMPT', nil),
      'workflow' => ENV.fetch('GITHUB_WORKFLOW', nil),
      'commit' => ENV.fetch('GITHUB_SHA', nil)
    }.compact
  end

  def stage(question, responses)
    responses.to_h { |response| [response.provider.to_s, response_entry(question, response)] }
  end

  def response_entry(question, response)
    response.data.merge('value' => parsed_value(question, response))
  end

  # The forecast value in the type's output format, or nil if it can't be
  # parsed (the raw content is still recorded).
  def parsed_value(question, response)
    case question.type
    when 'binary' then response.probability
    when 'numeric', 'discrete' then response.percentiles.transform_keys(&:to_s)
    when 'multiple_choice' then response.probabilities
    end
  rescue StandardError
    nil
  end

  def news(post_id)
    summary_path = cache_path(post_id, 'outputs/news_summary.md')
    {
      'summary' => File.exist?(summary_path) ? File.read(summary_path) : nil,
      'items' => cached_json(post_id, 'news.json')
    }
  end

  def cached_json(post_id, path)
    full_path = cache_path(post_id, path)
    File.exist?(full_path) ? JSON.parse(File.read(full_path)) : nil
  rescue JSON::ParserError
    nil
  end
end
