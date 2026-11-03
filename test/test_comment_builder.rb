# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/comment_builder'

class TestCommentBuilder < Minitest::Test
  POST_ID = 'test_comment_builder'

  def setup
    init_cache(POST_ID)
  end

  def teardown
    FileUtils.rm_rf("./tmp/#{POST_ID}")
  end

  def response(provider, pct)
    body = { 'choices' => [{ 'message' => { 'content' => "<probability>\n#{pct}%\n</probability>" } }] }
    Response.new(provider, json: body.to_json)
  end

  def binary_question
    Metaculus::Question.new(data: { 'question' => { 'type' => 'binary' } })
  end

  def test_pre_revision_reads_the_original_forecast
    File.write(cache_path(POST_ID, 'forecasts/forecast.openai.json'), response(:openai, 28).data.to_json)
    out = CommentBuilder.build_forecaster_positions(POST_ID, binary_question, [response(:openai, 23)])
    assert_includes out, 'value="23.0%" pre_revision="28.0%"'
  end

  # A missing original must not masquerade as "no Delphi movement".
  def test_pre_revision_is_na_when_original_missing
    out = nil
    _, err = capture_io do
      out = CommentBuilder.build_forecaster_positions(POST_ID, binary_question, [response(:openai, 23)])
    end
    assert_includes out, 'value="23.0%" pre_revision="N/A"'
    assert_match(/no original forecast for openai/, err)
  end
end
