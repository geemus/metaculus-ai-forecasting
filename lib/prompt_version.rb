# frozen_string_literal: true

require 'digest'

# A short content hash of every prompt source file. It changes only when a
# prompt changes (not on unrelated commits) and needs no git checkout, so the
# retro can group resolved questions by the prompts that actually produced
# them. Each stage stamps its cached output with this when it generates, which
# matters because stage outputs are cached per post and reused by later runs.
module PromptVersion
  ROOT = File.expand_path('..', __dir__)

  module_function

  def files(root: ROOT)
    [File.join(root, 'lib/prompts.rb'), *Dir[File.join(root, 'lib/prompt_templates/*.erb')]]
  end

  def compute(root: ROOT)
    digest = Digest::SHA256.new
    files(root: root).each do |path|
      digest << path.delete_prefix("#{root}/") << "\0" << File.binread(path) << "\0"
    end
    digest.hexdigest[0, 12]
  end

  CURRENT = compute

  # Fields merged into a stage's cached JSON when it is generated. `commit`
  # (the CI run's git SHA) lets a human map a version back to the code.
  def stamp
    { 'prompt_version' => CURRENT, 'commit' => ENV['GITHUB_SHA']&.slice(0, 7) }.compact
  end

  # The overall version recorded in a pipeline comment's <prompt_version>
  # element: a hash, "mixed", or "unknown" when the comment predates stamping.
  def from_comment(text)
    text.to_s[%r{<prompt_version[^>]*>([^<]*)</prompt_version>}, 1]&.strip || 'unknown'
  end

  # Retro prompt section telling the reviewer which questions ran under the
  # prompts it is shown, so it does not judge current text against forecasts
  # that earlier prompts produced.
  def retro_section(versions, current: CURRENT)
    counts = versions.tally.sort_by { |version, n| [version == current ? 0 : 1, -n] }
    lines = counts.map do |version, n|
      label = version == current ? ' (current — the prompts shown below)' : ''
      "- `#{version}`#{label}: #{n} question#{'s' unless n == 1}"
    end
    <<~SECTION
      ## Prompt Versions

      Each `<forecast>` carries a `<prompt_version>`: a hash of the prompt files that produced it. "unknown" means the forecast predates version stamping; "mixed" means its stages ran under different versions (the comment's `<prompt_version>` element lists each stage). The current version is `#{current}`.

      #{lines.join("\n")}

      Only questions at the current version ran under the prompts shown below. Base claims that a current instruction is failing, and every Remove-or-merge proposal, on those questions alone. For questions at any other version, ask instead whether the current prompts would have prevented the error; if they already would, say so rather than recommending a change. If fewer than 3 questions are at the current version, say so and keep recommendations to patterns the current prompts do not already address.
    SECTION
  end
end
