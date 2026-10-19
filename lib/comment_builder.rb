# frozen_string_literal: true

require_relative 'asknews'

module CommentBuilder
  MAX_COMMENT_LENGTH = 10_000

  module_function

  def build_pipeline_comment(post_id, question, consensus_response, revised_forecasts)
    baseline = begin
      mechanical_baseline(question, revised_forecasts)
    rescue StandardError
      nil
    end

    sections = [
      build_pipeline_overview(post_id, question, baseline),
      build_news_summary(post_id),
      build_research_summary(post_id),
      build_forecaster_positions(post_id, question, revised_forecasts),
      build_consensus_analysis(consensus_response),
      build_final_forecast(question, consensus_response)
    ]

    comment = sections.join("\n\n---\n\n")
    truncate_if_needed(comment)
  end

  # ─── Pipeline Overview ───────────────────────────────────────────────

  def build_pipeline_overview(post_id, question, baseline)
    news_meta = news_metadata(post_id)

    lines = []
    lines << '## Pipeline Overview'
    lines << "- **Question**: #{question.title}"
    lines << "- **Type**: #{question.type}"
    lines << "- **Post ID**: #{post_id}"
    lines << "- **Stages**: News → Research → #{Provider::FORECASTERS.size} Forecasters → Delphi Revise → Consensus"
    lines << "- **News**: #{news_meta}" if news_meta
    lines << "- **Mechanical Baseline**: #{baseline.split("\n").first}" if baseline
    lines.join("\n")
  end

  # ─── News Summary ────────────────────────────────────────────────────

  def build_news_summary(post_id)
    summary_path = cache_path(post_id, 'outputs/news_summary.md')

    content = if File.exist?(summary_path)
                File.read(summary_path).strip
              else
                fallback_news_summary(post_id)
              end

    content = '_No news summary available._' if content.nil? || content.empty?

    "## News Summary\n<news_summary>\n#{content}\n</news_summary>"
  end

  def fallback_news_summary(post_id)
    news_path = cache_path(post_id, 'news.json')
    return nil unless File.exist?(news_path)

    news = JSON.parse(File.read(news_path))
    blocks = AskNews.blocks(news)
    return nil if blocks.values.all?(&:empty?)

    top_titles = blocks.values.flat_map { |articles| articles.first(2) }
                       .map { |a| "- #{a['eng_title']}" }.join("\n")

    "#{news_block_counts(blocks)}. Top articles (recent first):\n#{top_titles}"
  rescue StandardError
    nil
  end

  # ─── Research Summary ────────────────────────────────────────────────

  def build_research_summary(post_id)
    research_path = cache_path(post_id, 'research.json')

    unless File.exist?(research_path)
      return "## Research Summary\n<research_summary>\n_No research data available._\n</research_summary>"
    end

    research_json = File.read(research_path)
    research = Response.new(:open_router, json: research_json)
    summary = research.extracted_content('research_summary')

    if summary && !summary.empty?
      return "## Research Summary\n<research_summary>\n#{summary}\n</research_summary>"
    end

    # Fallback: extract ### 1-4 sections into bullet points
    fallback = fallback_research_summary(research.content)
    "## Research Summary\n<research_summary>\n#{fallback || '_Could not extract research summary._'}\n</research_summary>"
  rescue StandardError => e
    "## Research Summary\n<research_summary>\n_Error loading research: #{e.message}_\n</research_summary>"
  end

  def fallback_research_summary(content)
    return nil if content.nil? || content.empty?

    sections = content.scan(/^###\s+\d+\.?\s*(.+?)\n((?:(?!^###\s).*\n?)*)/)
    return nil if sections.empty?

    bullets = sections.first(4).map do |heading, body|
      # Truncate each section body to first 2 sentences
      sentences = body.strip.split(/(?<=[.!?])\s+/)
      truncated = sentences.first(2).join(' ').strip
      truncated = truncated[0..200] if truncated.length > 200
      "- **#{heading.strip}**: #{truncated}"
    end

    "_Automatically extracted from research sections (research_summary tag missing):_\n#{bullets.join("\n")}"
  rescue StandardError
    nil
  end

  # ─── Forecaster Positions ────────────────────────────────────────────

  def build_forecaster_positions(post_id, question, forecasts)
    originals = load_original_forecasts(post_id)

    elements = forecasts.map do |forecast|
      provider = forecast.provider.to_s
      value = format_forecast_value(question, forecast)

      # Find matching original forecast to get pre_revision value
      original = originals.find { |o| o.provider == forecast.provider }
      pre_revision = if original
                       format_forecast_value(question, original)
                     else
                       value # fallback if original not available
                     end

      confidence = forecast.extracted_content('confidence') || 'N/A'
      argument = extract_key_argument(forecast)

      %(<forecaster provider="#{xml_escape(provider)}" value="#{xml_escape(value)}" pre_revision="#{xml_escape(pre_revision)}" confidence="#{xml_escape(confidence)}">\n#{xml_escape(argument)}\n</forecaster>)
    end

    ["## Forecaster Positions", *elements].join("\n")
  end

  def load_original_forecasts(post_id)
    Provider::FORECASTERS.map do |provider|
      forecast_path = cache_path(post_id, "forecasts/forecast.#{provider}.json")
      next unless File.exist?(forecast_path)

      Response.new(provider, json: File.read(forecast_path))
    end.compact
  rescue StandardError => e
    warn "WARNING: failed to load original forecasts: #{e.message}"
    []
  end

  def extract_key_argument(forecast)
    argument = forecast.extracted_content('forecast_summary')

    # Fallback to first sentence of think if forecast_summary is missing
    if argument.nil? || argument.empty?
      think = forecast.extracted_content('think')
      argument = if think && !think.empty?
                   first_sentence = think.split(/(?<=[.!?])\s+/).first
                   first_sentence.to_s.strip[0..150]
                 else
                   # Last resort: first sentence of non-tag content
                   stripped = forecast.stripped_content('think', 'forecast_summary', 'confidence',
                                                        'probability', 'percentiles', 'probabilities',
                                                        'calibration_disclaimer')
                   first_sentence = stripped.split(/(?<=[.!?])\s+/).first
                   first_sentence.to_s.strip[0..150]
                 end
    end

    argument = argument.to_s.strip[0..150]
    argument = argument.gsub("\n", ' ') # Flatten newlines
    argument = '_No argument available_' if argument.empty?

    argument
  end

  def format_forecast_value(question, forecast)
    case question.type
    when 'binary'
      pct = (forecast.probability * 100).round(1)
      "#{pct}%"
    when 'numeric', 'discrete'
      percentiles = forecast.percentiles
      p50 = percentiles[50]
      units = question.units.to_s.empty? ? '' : " #{question.units}"
      "#{p50}#{units}"
    when 'multiple_choice'
      probs = forecast.probabilities
      top = probs.max_by { |_k, v| v }
      "#{top[0]}: #{(top[1] * 100).round(1)}%"
    else
      'N/A'
    end
  rescue StandardError
    'N/A'
  end

  # ─── Consensus Analysis ──────────────────────────────────────────────

  def build_consensus_analysis(consensus_response)
    think = consensus_response.extracted_content('think')

    content = if think && !think.empty?
                think
              else
                # Fall back to stripped content (entire response minus XML tags)
                consensus_response.stripped_content('think')
              end

    content = '_No analysis available._' if content.nil? || content.strip.empty?

    "## Consensus Analysis\n<consensus_analysis>\n#{content.strip}\n</consensus_analysis>"
  end

  # ─── Final Forecast ──────────────────────────────────────────────────

  def build_final_forecast(question, consensus_response)
    content = consensus_response.content

    xml_block = case question.type
                when 'binary'
                  extract_xml_block(content, 'probability')
                when 'numeric', 'discrete'
                  extract_xml_block(content, 'percentiles')
                when 'multiple_choice'
                  extract_xml_block(content, 'probabilities')
                end

    forecast_text = if xml_block
                      xml_block.strip
                    else
                      '_Forecast value not found in response._'
                    end

    "## Final Forecast\n#{forecast_text}"
  end

  # ─── Helpers ─────────────────────────────────────────────────────────

  def news_metadata(post_id)
    news_path = cache_path(post_id, 'news.json')
    return nil unless File.exist?(news_path)

    news = JSON.parse(File.read(news_path))
    blocks = AskNews.blocks(news)
    return nil if blocks.values.all?(&:empty?)

    news_block_counts(blocks)
  rescue StandardError
    nil
  end

  # Counts are of the raw search results in news.json, before news.rb filters
  # and caps each block for the prompt.
  def news_block_counts(blocks)
    background = blocks['archive']
    dates = background.map { |a| a['pub_date'] }.compact.sort
    range = dates.any? ? " (#{dates.first[0..9]} to #{dates.last[0..9]})" : ''
    "#{blocks['latest'].length} from last 48h, #{background.length} background#{range}"
  end

  def extract_xml_block(text, tag)
    match = text.match(%r{<#{tag}>[\s\S]*?</#{tag}>})
    match&.[](0)
  end

  def xml_escape(value)
    value.to_s
         .gsub('&', '&amp;')
         .gsub('<', '&lt;')
         .gsub('>', '&gt;')
         .gsub('"', '&quot;')
  end

  def truncate_if_needed(comment)
    return comment if comment.length <= MAX_COMMENT_LENGTH

    # Truncate content within XML blocks, preserving tags and headers.
    # Order: news_summary, research_summary, consensus_analysis, then forecaster content.
    truncate_targets = %w[news_summary research_summary consensus_analysis]
    truncate_targets.each do |tag|
      break if comment.length <= MAX_COMMENT_LENGTH

      comment = comment.sub(%r{<#{tag}>[\s\S]*?</#{tag}>}) do |match|
        inner = match.gsub(%r{</?#{tag}>}, '').strip
        truncated = inner[0..500] + "...\n_(truncated for length)_"
        "<#{tag}>\n#{truncated}\n</#{tag}>"
      end
    end

    # If still too long, truncate forecaster block contents
    if comment.length > MAX_COMMENT_LENGTH
      comment = comment.gsub(%r{<forecaster[^>]*>[\s\S]*?</forecaster>}) do |match|
        match.sub(%r{(<forecaster[^>]*>)([\s\S]*?)(</forecaster>)}) do
          opening = Regexp.last_match(1)
          content = Regexp.last_match(2).strip
          closing = Regexp.last_match(3)
          truncated = content.length > 200 ? content[0..200] + '...' : content
          "#{opening}#{truncated}\n#{closing}"
        end
      end
    end

    # Hard truncate at a safe boundary if still too long
    if comment.length > MAX_COMMENT_LENGTH
      safe_end = comment.rindex("\n", MAX_COMMENT_LENGTH - 50) || MAX_COMMENT_LENGTH - 50
      comment = comment[0...safe_end] + "\n\n...\n_(comment truncated to fit length limit)_"
    end

    comment
  end
end
