# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/comment_builder'

class TestPromptVersion < Minitest::Test
  POST_ID = 'test_prompt_version'

  def setup
    init_cache(POST_ID)
  end

  def teardown
    FileUtils.rm_rf("./tmp/#{POST_ID}")
  end

  def with_prompt_tree
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'lib/prompt_templates'))
      File.write(File.join(root, 'lib/prompts.rb'), 'SYSTEM = 1')
      File.write(File.join(root, 'lib/prompt_templates/a.erb'), 'template a')
      yield root
    end
  end

  def response(provider, pct, version: nil)
    body = { 'choices' => [{ 'message' => { 'content' => "<probability>\n#{pct}%\n</probability>" } }] }
    body['prompt_version'] = version if version
    Response.new(provider, json: body.to_json)
  end

  def write_stage(path, version)
    File.write(cache_path(POST_ID, path), response(:openai, 30, version: version).data.to_json)
  end

  # ─── hashing ───────────────────────────────────────────────────────────────

  def test_current_version_is_short_hex
    assert_match(/\A\h{12}\z/, PromptVersion::CURRENT)
  end

  def test_version_is_stable_for_unchanged_prompts
    with_prompt_tree do |root|
      assert_equal PromptVersion.compute(root: root), PromptVersion.compute(root: root)
    end
  end

  def test_version_changes_when_any_prompt_file_changes
    with_prompt_tree do |root|
      before = PromptVersion.compute(root: root)
      File.write(File.join(root, 'lib/prompt_templates/a.erb'), 'template a, edited')
      refute_equal before, PromptVersion.compute(root: root)
    end
  end

  def test_version_changes_when_a_template_is_added
    with_prompt_tree do |root|
      before = PromptVersion.compute(root: root)
      File.write(File.join(root, 'lib/prompt_templates/b.erb'), 'template b')
      refute_equal before, PromptVersion.compute(root: root)
    end
  end

  # ─── stamping ──────────────────────────────────────────────────────────────

  def test_stamp_records_version_and_short_commit
    ENV['GITHUB_SHA'] = 'abcdef1234567890'
    assert_equal({ 'prompt_version' => PromptVersion::CURRENT, 'commit' => 'abcdef1' }, PromptVersion.stamp)
  ensure
    ENV.delete('GITHUB_SHA')
  end

  def test_stamp_omits_commit_outside_ci
    ENV.delete('GITHUB_SHA')
    assert_equal({ 'prompt_version' => PromptVersion::CURRENT }, PromptVersion.stamp)
  end

  def test_response_stamp_survives_cache_round_trip
    json = response(:openai, 30).stamp_prompt_version!.to_json
    assert_equal PromptVersion::CURRENT, Response.new(:openai, json: json).prompt_version
  end

  def test_unstamped_response_has_no_version
    assert_nil response(:openai, 30).prompt_version
  end

  # ─── pipeline comment ──────────────────────────────────────────────────────

  def test_comment_element_reports_shared_version
    write_stage('research.json', 'aaa')
    write_stage('forecasts/forecast.openai.json', 'aaa')
    out = CommentBuilder.build_prompt_version(POST_ID, response(:deepseek, 30, version: 'aaa'),
                                              [response(:openai, 30, version: 'aaa')])
    assert_equal '<prompt_version research="aaa" forecast="aaa" revision="aaa" consensus="aaa">aaa</prompt_version>', out
  end

  # Cached stages can be reused by a later run under newer prompts.
  def test_comment_element_reports_mixed_versions_per_stage
    write_stage('research.json', 'old')
    write_stage('forecasts/forecast.openai.json', 'old')
    out = CommentBuilder.build_prompt_version(POST_ID, response(:deepseek, 30, version: 'new'),
                                              [response(:openai, 30, version: 'new')])
    assert_includes out, 'research="old"'
    assert_includes out, 'consensus="new"'
    assert out.end_with?('>mixed</prompt_version>'), out
  end

  def test_comment_element_marks_unstamped_stages_unknown
    out = CommentBuilder.build_prompt_version(POST_ID, response(:deepseek, 30), [response(:openai, 30)])
    assert_includes out, 'research="unknown"'
    assert out.end_with?('>unknown</prompt_version>'), out
  end

  def test_overview_includes_prompt_version
    question = Metaculus::Question.new(data: { 'question' => { 'type' => 'binary', 'title' => 'T' } })
    out = CommentBuilder.build_pipeline_overview(POST_ID, question, nil, response(:deepseek, 30), [])
    assert_includes out, '- **Prompt Version**: <prompt_version '
  end

  # ─── retro ─────────────────────────────────────────────────────────────────

  def test_from_comment_reads_element_text
    comment = "## Pipeline Overview\n- **Prompt Version**: <prompt_version research=\"a\" consensus=\"a\">a1b2c3</prompt_version>"
    assert_equal 'a1b2c3', PromptVersion.from_comment(comment)
  end

  def test_from_comment_defaults_to_unknown
    assert_equal 'unknown', PromptVersion.from_comment('no stamp here')
    assert_equal 'unknown', PromptVersion.from_comment(nil)
  end

  def test_retro_section_counts_versions_and_flags_current
    section = PromptVersion.retro_section(%w[cur cur old unknown], current: 'cur')
    assert_includes section, '- `cur` (current — the prompts shown below): 2 questions'
    assert_includes section, '- `old`: 1 question'
    assert_includes section, '- `unknown`: 1 question'
    assert_includes section, 'every Remove-or-merge proposal, on those questions alone'
  end
end
