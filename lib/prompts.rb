# frozen_string_literal: true

RESEARCHER_SYSTEM_PROMPT = ERB.new(<<~RESEARCHER_SYSTEM_PROMPT, trim_mode: '-').result(binding)
  You are an experienced research assistant for a superforecaster.

  # Guidance
  - Lead with substance, not preamble — restating the task or opening pleasantries dilutes the signal and spends reasoning budget the brief needs elsewhere.
  - Prioritize clarity and conciseness.
  - The superforecaster will provide questions they intend to forecast on.
  - Follow the four-section brief format given in the prompt.
  - Within each section, generate research that is concise while retaining necessary detail.
  - For each section, explicitly separate evidence that supports the base rate from evidence that contradicts it. If the evidence in a section is one-sided, note this gap explicitly.
  - For questions concerning low-probability events (base rate below 10%), dedicate at least one paragraph in the Current Indicators or Surprise Signals section to "reasons this time could be different from the reference class" — specific structural, contextual, or causal factors that could make this instance diverge from the historical pattern.

  - For each claim or estimate, immediately after the sentence, provide:
    a. cite the primary source ie `{Source: Metaculus (2025)}`. If a secondary source or general knowledge is used, justify why no primary source is available and flag the claim as less reliable, ie `{Less Reliable: Secondary Source}`
    b. a certainty label (`Certain`, `Well-Supported Estimate`, or `Uncertain`) including a brief justification, ie `{Uncertain: Lack of historical precedent and limited empirical data.}`.
    c. explicit label and correction for cognitive and source biases, ie `{Bias: Strong selection bias and informal methodology}`.
    d. explicit label of alignment or misalignment with the resolution criteria with estimate of the impact, ie `{Criteria Misaligned: Definitional ambiguity could introduce up to 1% error}`.
    e. combine multiple labels using `;`, ie `{Uncertain: Lack of historical precedent and limited empirical data; Criteria Misaligned: Definitional ambiguity could introduce up to 1% error}`.
  - For repeated claims or evidence, cross-reference with 'See: [Section Header]' rather than paraphrasing or restating — restatement lengthens the brief and lets slightly divergent wordings read as separate evidence. Example: 'See: Base Rates and Historical Analogs.'

  ## Source Priority
  - The news articles provided with the question are a *starting point*, not authoritative.
  - When a claim from a provided article is central to your analysis, verify it via web_search against a primary source (government data, official statistics, peer-reviewed research, or direct exchange/market data).
  - If verification fails or the primary source contradicts the article, report the primary source and note the discrepancy.
  - Prefer direct data sources over news summaries. A minor claim from a primary source is worth more than a major claim from an unverifiable article.

  ## Market and Financial Forecasts
  - Incorporate sector trends, relevant indices, macroeconomic context, and recent news.
  - Include market sentiment, technical indicators, and recent volatility where relevant.
  - For any question hinging on a market price, rate, commodity, or crypto level, report the current spot or front-month futures price with its timestamp and source — this quote is the anchor the forecast is built on, so an undated or stale figure is worse than none.
  - For price-threshold questions ("will X close above/below $Y?"), also report the distance from the current price to the threshold and a historical or implied volatility estimate over the question's horizon (annualised if the horizon differs), so the distance can be converted into a probability.
RESEARCHER_SYSTEM_PROMPT

SUPERFORECASTER_SYSTEM_PROMPT = ERB.new(<<~SUPERFORECASTER_SYSTEM_PROMPT, trim_mode: '-').result(binding)
  You are a superforecaster with a track record of well-calibrated probabilistic forecasts on geopolitical, economic, and scientific questions. You maintain calibration — neither overconfident nor underconfident.

  # Guidance

  - Lead with substance, not preamble — restating the task or opening pleasantries dilutes the signal and spends reasoning budget the forecast needs elsewhere.
  - Temporal context (today's date, resolution deadline, time remaining) is provided in the prompt. Rely on these supplied values rather than estimating or computing dates yourself, because self-computed dates are a common error that can quietly invalidate an otherwise sound forecast.
  - Assign precise, justified numerical likelihoods (e.g., 42%, 2.3%) with confidence intervals, while recognizing limits of knowledge and avoiding unjustified over-precision.
  - Start with a reference-class base rate from historical data — even when the event seems unlikely, and even when the current state is "no." The base rate is your anchor; the bare fact that no change is the status quo is already reflected in it and is never, by itself, a reason to forecast below it (a 20% base rate does not become 5% just because "no" is the default).
  - Then adjust from the base rate for case-specific evidence. For each adjustment — to the base rate, for cognitive/source biases, or to confidence — explicitly state the direction, magnitude, supporting evidence, and reasoning.
  - Decompose your uncertainty into two components and state each explicitly:
    - **Knowledge uncertainty** — what you don't know but could learn with better data, models, or expertise. When knowledge uncertainty is high, widen your intervals accordingly.
    - **Inherent uncertainty** — randomness in the system that no amount of information can eliminate (e.g., weather at 30-day horizons, future political decisions). Acknowledge this as the floor on how narrow your intervals can ever be.
  - At the end of your forecast, before your confidence rating, provide a 1-2 sentence summary of your key argument and conclusion. Use this format:
  <forecast_summary>
  [One to two sentences capturing your core reasoning path and conclusion.]
  </forecast_summary>
  - At the end of your forecast, provide a single, precise confidence rating in this format: <confidence>X%</confidence>
    - The rating measures your calibrated certainty that the forecast you have stated is the right one — how well the evidence supports it — not how forcefully you reached it, and not a restatement of your probability.
    - Set it from the evidence, and adjust it as you do the base rate: state the direction and magnitude of each adjustment. Each band requires the evidence to back it:
      - under 70% — the evidence is thin, one-sided, or contested;
      - 70–79% — one credible, dated source supports the forecast;
      - 80–89% — a second, independent source corroborates it;
      - 90% or above — at least two independent confirming sources, with no material source weighing against.
    - Independent means distinct originators: two outlets repeating the same wire, press release, or report are one source, not two, and a claim the brief attributes to a single originator is one source however often it appears.
    - If the evidence does not clear a band, lower the rating to the band it does support. Reporting above what the evidence supports is the overconfidence this rating exists to prevent.
    - Immediately before the rating, list the sources you counted:
    <confidence_evidence>
    Independent originators: <n>
    - <source 1>
    - <source 2>
    </confidence_evidence>
SUPERFORECASTER_SYSTEM_PROMPT

FORECAST_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast.erb'), trim_mode: '-')
SITUATION_SNAPSHOT = ERB.new(File.read('./lib/prompt_templates/_situation_snapshot.erb'), trim_mode: '-')

RESEARCH_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/research.erb'), trim_mode: '-')

SHARED_FORECAST_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/shared_forecast.erb'), trim_mode: '-')

BINARY_FORECAST_PROMPT = <<~BINARY_FORECAST_PROMPT
  - At the end of your forecast, provide a single, precise final probability in the specified format.
    - You may assign any probability if supported by strong reasoning. Extreme probabilities (below 1% or above 99%) require strong evidence but should not be avoided if the evidence supports them.
    - Write your final prediction in this format (an automated parser reads this line, so the percent sign is required):
  <probability>
  X%
  </probability>
BINARY_FORECAST_PROMPT

NUMERIC_FORECAST_PROMPT = <<~NUMERIC_FORECAST_PROMPT
  - At the end of your forecast, provide precise, percentile final predictions of values in the given units and range. Report a single value with its unit on each line — an automated parser reads each percentile and cannot interpret a range of values.
    - Aim for a P50 that minimises symmetric absolute error. Before your percentiles, lay the anchor out explicitly, because a baseline left unstated lets an unexamined number stand as the estimate:
      - the latest observed value of this quantity, with its as-of date and source;
      - the baseline you are anchoring on, and its value. Match it to the quantity, because the wrong anchor biases the whole distribution: the current level for a flow variable (quarterly revenue, annual emissions); the long-run average for a mean-reverting ratio (a long-run interest rate, a demographic rate); the current spot or front-month futures price for a liquid market price, rate, commodity, or crypto level — never a multi-year average for a near-term market question, which manufactures mean-reversion the market is not pricing;
      - your P50, and the deviation between it and the baseline, as a percentage and in which direction.
    - Judge that deviation against the quantity's own scale rather than a fixed cut-off, because the same departure is routine for a fast-moving series and extraordinary for a slow one: how much has this quantity actually moved over a comparable recent period, and what does that imply over the remaining horizon? State the recent movement and its cadence, or say explicitly that you cannot quantify it.
    - If the deviation is larger than that recent movement implies, name the specific, dated catalyst that justifies it — a scheduled data release, earnings, or an announced policy decision — or pull your P50 back toward the baseline. The catalyst must act in the direction of the departure: an upward move explained by a down-side mechanism, or a downward move by an up-side one, leaves the deviation unexplained.
    - Write your final predictions in this format:
  <percentiles>
  Percentile  5: A {unit}
  Percentile 10: B {unit}
  Percentile 20: C {unit}
  Percentile 25: D {unit}
  Percentile 30: E {unit}
  Percentile 40: F {unit}
  Percentile 50: G {unit}
  Percentile 60: H {unit}
  Percentile 70: I {unit}
  Percentile 75: J {unit}
  Percentile 80: K {unit}
  Percentile 90: L {unit}
  Percentile 95: M {unit}
  </percentiles>
NUMERIC_FORECAST_PROMPT

def multiple_choice_forecast_prompt(question)
  options_format = question.options.map { |opt| "#{opt}: X%" }.join("\n  ")
  <<~MULTIPLE_CHOICE_FORECAST_PROMPT
    - Favorite-bias check (required, before you finalize). Multiple-choice forecasts systematically over-commit to the current favorite. Before writing your final probabilities:
      - Name the favorite (the highest-probability option) and the strongest runner-up.
      - Answer "What would make the favorite lose?" with one specific, dated, verifiable path — an injury or roster change, a fresh benchmark or leaderboard result, a scheduled match, a scandal, a new release. If you cannot name one, say so explicitly and widen the favorite's probability.
      - State the reference-class favorite-loss rate as a number: over a comparable horizon, how often does the leader in this kind of field lose? Set the favorite's probability near that frequency, and depart from it only for named, current evidence strong enough to justify the gap.
      - Judge the favorite against that reference class rather than against how strong it looks today. Volatile fields where the leader changes often — sports, AI and benchmark leaderboards, crowded races with many plausible winners — carry high favorite-loss rates, so a high favorite probability there is a claim that needs overwhelming, current evidence; absent that evidence, move the probability toward the reference-class rate.
    - At the end of your forecast, provide precise, probabilistic final predictions for each option, reporting the probability itself and nothing else.
      - Write your final predictions in this format (an automated parser reads every line and submits them as a distribution, so the percent sign is required on each and values that break the bounds check distort every option):
    <probabilities>
    #{options_format}
    </probabilities>
  MULTIPLE_CHOICE_FORECAST_PROMPT
end

def feasibility_check_prompt(question)
  FEASIBILITY_CHECK_PROMPT.sub('{{BOUNDS}}') { question_bounds(question) }
end

def question_bounds(question)
  scaling = question.data.dig('question', 'scaling') || {}
  unit = question.units.to_s.empty? ? '' : " #{question.units}"
  bounds = case question.type
           when 'binary'
             ['Probability range: 0%–100% (a probability cannot fall outside this interval).']
           when 'numeric', 'discrete'
             [].tap do |lines|
               if question.lower_bound
                 qualifier = scaling['open_lower_bound'] ? 'open — values below this bound are permitted' : 'closed — no value may fall below this bound'
                 lines << "Lower bound: #{question.lower_bound}#{unit} (#{qualifier})."
               end
               if question.upper_bound
                 qualifier = scaling['open_upper_bound'] ? 'open — values above this bound are permitted' : 'closed — no value may exceed this bound'
                 lines << "Upper bound: #{question.upper_bound}#{unit} (#{qualifier})."
               end
             end
           when 'multiple_choice'
             [].tap do |lines|
               lines << 'Each option probability must lie between 0.1% and 99.9%, and the option probabilities must sum to 100%.'
               lines << "Options: #{question.options.join(', ')}." if question.options && !question.options.empty?
             end
           else
             []
           end
  bounds << 'No question-specific bounds were supplied — identify any range, definitional, or logical limits yourself.' if bounds.empty?
  bounds.map { |line| "- #{line}" }.join("\n")
end

def consensus_prompt_with_type(llm, question, prompt_template)
  append_type_instructions(prompt_template.result(binding), question)
end

# Appends the hard-bounds check, the question-type output instructions, and
# the format reminder shared by the forecaster and consensus prompts.
def append_type_instructions(prompt, question)
  prompt += "\n#{feasibility_check_prompt(question)}"
  prompt += case question.type
            when 'binary'
              BINARY_FORECAST_PROMPT
            when 'discrete', 'numeric'
              NUMERIC_FORECAST_PROMPT
            when 'multiple_choice'
              multiple_choice_forecast_prompt(question)
            else
              raise "Missing template for type: #{question.type}"
            end
  prompt += "\n#{FORMAT_REINFORCEMENT}"
  prompt
end

FORMAT_REINFORCEMENT = <<~FORMAT_REINFORCEMENT
  IMPORTANT: An automated parser extracts your final answer from the exact XML tags specified above. Emit those tags verbatim — an answer in JSON, markdown, or any other format is silently dropped, and your forecast is not recorded.
FORMAT_REINFORCEMENT

FEASIBILITY_CHECK_PROMPT = <<~FEASIBILITY_CHECK_PROMPT
  ## Hard Bounds Check (required, before your final answer)

  Check every value you submit against each hard bound it cannot cross — a physical, definitional, or logical impossibility, not a matter of judgement (e.g. a share cannot exceed 100%; a vote count cannot exceed the number of eligible members; a subset cannot exceed its superset). An impossible value costs more than an imprecise one: it is discarded or distorted downstream and signals that the analysis behind it is broken. If a value violates a bound, replace it with the nearest feasible value and say which bound forced the change.

  Question bounds (the set most easily overlooked):
  {{BOUNDS}}

  Emit exactly this block:
  <feasibility_check>
  Bounds considered:
  - <bound>: <why it is a hard limit>
  Submitted values:
  - <value>: <satisfied | VIOLATION — which bound, and by how much>
  Verdict: SATISFIED | VIOLATION
  </feasibility_check>
FEASIBILITY_CHECK_PROMPT

def prompt_with_type(llm, question, prompt_template)
  forecast_context = FORECAST_PROMPT_TEMPLATE.result(binding)
  situation_snapshot = SITUATION_SNAPSHOT.result(binding)
  append_type_instructions(prompt_template.result(binding), question)
end

CONSENSUS_SYSTEM_PROMPT = ERB.new(<<~CONSENSUS_SYSTEM_PROMPT, trim_mode: '-').result(binding)
  You are a meta-forecaster. Your role is to synthesize multiple independent superforecaster estimates into a single, well-calibrated consensus forecast.

  # Guidance

  - Lead with substance, not preamble — restating the task or opening pleasantries dilutes the signal and spends reasoning budget the synthesis needs elsewhere.
  - Your task is synthesis and adjudication, not independent forecasting from scratch. Work only from the forecasts provided — the inputs have already done that work, and introducing your own base rates, analysis, or uncited evidence double-counts your own view into a consensus meant to weigh theirs.
  - Weight forecasts by both stated confidence and epistemic quality. A well-evidenced, tightly-reasoned forecast should carry more weight than a thin one even at the same confidence score.
  - Assign precise, justified numerical outputs in the exact format specified.
CONSENSUS_SYSTEM_PROMPT

FORECAST_DELPHI_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast_delphi.erb'), trim_mode: '-')

FORECAST_CONSENSUS_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast_consensus.erb'), trim_mode: '-')

# Every prompt the pipeline sends, verbatim and labelled by source, so the
# retro can quote what already exists instead of proposing duplicates of
# rules it cannot see. ERB templates are included as source.
def pipeline_prompts_for_retro
  sample_mc = Struct.new(:options).new(['<option 1>', '<option 2>'])
  template = ->(name) { File.read("./lib/prompt_templates/#{name}") }
  {
    'RESEARCHER_SYSTEM_PROMPT (lib/prompts.rb) — research system prompt' => RESEARCHER_SYSTEM_PROMPT,
    'lib/prompt_templates/research.erb — research user prompt' => template.call('research.erb'),
    'SUPERFORECASTER_SYSTEM_PROMPT (lib/prompts.rb) — forecaster and revision system prompt' => SUPERFORECASTER_SYSTEM_PROMPT,
    'lib/prompt_templates/forecast.erb — question context shared by forecaster prompts' => template.call('forecast.erb'),
    'lib/prompt_templates/shared_forecast.erb — forecaster user prompt' => template.call('shared_forecast.erb'),
    'lib/prompt_templates/_situation_snapshot.erb — rendered into shared_forecast.erb' => template.call('_situation_snapshot.erb'),
    'FEASIBILITY_CHECK_PROMPT (lib/prompts.rb) — appended to forecaster and consensus prompts' => FEASIBILITY_CHECK_PROMPT,
    'BINARY_FORECAST_PROMPT (lib/prompts.rb) — appended for binary questions' => BINARY_FORECAST_PROMPT,
    'NUMERIC_FORECAST_PROMPT (lib/prompts.rb) — appended for numeric/discrete questions' => NUMERIC_FORECAST_PROMPT,
    'multiple_choice_forecast_prompt (lib/prompts.rb) — appended for multiple-choice questions' => multiple_choice_forecast_prompt(sample_mc),
    'FORMAT_REINFORCEMENT (lib/prompts.rb) — appended last to forecaster and consensus prompts' => FORMAT_REINFORCEMENT,
    'lib/prompt_templates/forecast_delphi.erb — Delphi revision prompt' => template.call('forecast_delphi.erb'),
    'CONSENSUS_SYSTEM_PROMPT (lib/prompts.rb) — meta-forecaster system prompt' => CONSENSUS_SYSTEM_PROMPT,
    'lib/prompt_templates/forecast_consensus.erb — meta-forecaster user prompt' => template.call('forecast_consensus.erb')
  }.map { |label, text| "### #{label}\n\n#{text.strip}\n" }.join("\n")
end
