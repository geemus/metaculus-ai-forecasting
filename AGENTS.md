# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is a GitHub project hosted at https://github.com/geemus/metaculus-ai-forecasting.
The `gh` CLI is available and authenticated — use it for issues, PRs, and other GitHub operations.

## Commands

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Lint (CI runs this; -a applies safe autocorrections)
bundle exec rubocop -a

# Run a single forecast (post_id, provider name)
ruby forecast.rb <post_id> <provider>

# Run end-to-end pipeline for a question
ruby ete.rb <post_id>

# Run research phase only
ruby tools_research.rb <post_id>

# Run news gathering only
ruby news.rb <post_id>

# Generate consensus from existing forecasts
ruby consensus.rb <post_id>

# Use test question IDs (defined in lib/utility.rb) to avoid skip logic
# Binary: 578, Numeric: 14333, Multiple Choice: 22427, Discrete: 38880
ruby forecast.rb 578 openai
```

## Workflow

### Branching and PRs

- Always create a feature branch for new work. Never push directly to `main`.
- Name branches descriptively: `feature/<thing>`, `fix/<thing>`, `refactor/<thing>`.
- Open a PR from the feature branch against `main`. Use `gh pr create`.

### Issue spec sync

- Before writing code, smoke-test any new library API with a quick `ruby -e` one-liner. Specs in issues sometimes assume operators or functions that don't match the library's actual API. Verify first.
- When implementation diverges from the issue spec (different operators, function names, API shape, simplified approach), update the issue body to reflect what was actually built. The spec in the issue should stay accurate for future readers.
- Use `gh issue edit <n> --body-file -` to update the spec in-place.

## Architecture

This is a multi-stage AI forecasting pipeline that submits probability forecasts to [Metaculus](https://metaculus.com) tournaments. It runs on GitHub Actions (triggered by `tournament.yml` every 20 minutes) and uses multiple LLM providers in parallel to generate diverse, calibrated forecasts.

### Pipeline Stages

```
news.rb → tools_research.rb → forecast.rb (×3 forecasters) → revise_forecast.rb (×3) → consensus.rb
```

1. **News** (`news.rb`) - Fetches and categorizes relevant news via AskNews API
2. **Research** (`tools_research.rb`) - Deep research using Claude Opus with web search tools
3. **Forecast** (`forecast.rb`) - 3 independent forecasters (OpenAI, Gemini, DeepSeek)
4. **Revise** (`revise_forecast.rb`) - Each forecaster sees peers' estimates and revises
5. **Consensus** (`consensus.rb`) - Final consolidated forecast submitted to Metaculus, synthesized by DeepSeek (`deepseek-v4-pro`, the `DeepSeek` client default). This step is deliberately a cheap model: it combines the revised forecasts rather than reasoning from scratch.

### Key Files

- **`lib/provider.rb`** - Multi-provider LLM factory. `Provider::FORECASTERS` — the forecaster ensemble (`:openai`, `:gemini`, `:deepseek`) — is loaded from `forecasters.json`, the single source of truth that CI also reads directly. `:openai` and `:gemini` route through OpenRouter; `:deepseek` uses its own client. (`:anthropic` is retained as a provider, used by `tournament_retro.rb`, but is in neither the forecaster ensemble nor consensus, which runs on `:deepseek`. Perplexity is still used for web search in the research phase via the Agent API in `tools_research.rb`, but is no longer a forecaster.)
- **`lib/metaculus.rb`** - Metaculus API client. `Question` class wraps question data; handles all 4 question types (binary, numeric, discrete, multiple_choice).
- **`lib/prompts.rb`** - System prompts and ERB templates. `SUPERFORECASTER_SYSTEM_PROMPT` encodes the Bayesian methodology (base rates, explicit adjustments, uncertainty calibration).
- **`lib/response.rb`** - Parses LLM responses across providers. Extracts XML-tagged forecast values (`<probability>`, `<percentiles>`, `<probabilities>`).
- **`lib/tools.rb`** - Defines `CALCULATOR_TOOL` (safe arithmetic via Dentaku) and `Tools.dispatch` (centralized tool-call router used by OpenRouter and DeepSeek). Web search is centralized upstream in the research phase, so forecasters have no search tool.
- **`lib/prompt_version.rb`** - Content hash of `lib/prompts.rb` + `lib/prompt_templates/*`. Each stage stamps it into its cached JSON when it generates (cached stages are reused across runs), the pipeline comment records it per stage in `<prompt_version>`, and the retro groups questions by it.
- **`lib/utility.rb`** - File-based caching in `tmp/{post_id}/`. All prompts and outputs are cached for auditability.

### Question Types & Output Formats

| Type | Format | Example |
|------|--------|---------|
| Binary | `<probability>X%</probability>` | Yes/No questions |
| Numeric | `<percentiles>` with 11 values (5,10,20,...,95) | Continuous range |
| Discrete | Same as numeric (mapped to named categories) | Named buckets |
| Multiple Choice | `<probabilities>` summing to 100% | Named options |

### Caching

All intermediate data is cached in `tmp/{post_id}/`:
- `post.json` - Question data
- `research.json` - Research output
- `news.json` - News items
- `inputs/` - Prompts sent to LLMs
- `outputs/` - Raw LLM responses
- `forecasts/` - Parsed forecast JSON
- `consensus/` - Final consensus data

### Required Environment Variables

```
ANTHROPIC_API_KEY
DEEPSEEK_API_KEY
OPEN_ROUTER_API_KEY
PERPLEXITY_API_KEY
ASKNEWS_API_KEY
METACULUS_BOT_API_TOKEN
METACULUS_BOT_ID
```
