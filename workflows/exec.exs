# A five-phase workflow: fetch a GitHub issue containing a plan, implement it,
# review the implementation, create a pull request, and post the review summary
# as a PR comment.
#
# This workflow assumes a Ruby project. The :test sensor runs `bundle exec rake test`.
# For other project types, create a custom workflow with appropriate sensors.
#
# Architecture:
#
#   Phase 1 (fetch_issue) — deterministic. Shells out to `gh issue view` to
#     fetch the issue body, title, and URL. No LLM. Outputs :plan, :issue_title,
#     and :issue_ref artifacts.
#
#   Phase 2 (implement) — agentic, 3 messages. Reads :plan and produces
#     :implementation_summary (file/change summary), :branch_name (git branch
#     name derived from the plan), and :pr_title (one-line PR title ~80 chars).
#     Sensors (test) run after; on failure, feedback loops back into
#     the sub-session for fixes (max 3 retries).
#
#   Phase 3 (review) — agentic, 2 messages. Reads :plan, :implementation_summary,
#     and :pr_title. Produces :comment_body (what was checked/found/fixed) and
#     :revised_pr_title (updated PR title if scope changed, otherwise repeats
#     the original). The distinct :revised_pr_title key preserves :pr_title for
#     fallback. Sensors (test) run after with retry (max 3 retries).
#
#   Phase 4 (create_pr) — deterministic. Reads :branch_name, :revised_pr_title,
#     :pr_title, :plan, :implementation_summary, :issue_ref, and
#     :task. Sanitizes the branch name, resolves the PR title (preferring
#     :revised_pr_title with :pr_title fallback), assembles a formatted PR body,
#     then sequences git checkout/add/commit/push and gh pr create. No LLM.
#     Outputs :pr_url.
#
#   Phase 5 (comment_pr) — deterministic. Reads :pr_url and :comment_body
#     from artifacts. Posts the review summary as a PR comment via
#     `gh pr comment`. Does not halt on failure.
[
  # --- Phase 1: Fetch GitHub issue (deterministic) ---
  %{
    name: :fetch_issue,
    run: {Retcon.Workflow.GitHub, :fetch_issue, []},
    context_inputs: [:task]
  },
  # --- Phase 2: Implement the plan ---
  %{
    name: :implement,
    system_prompt: """
    You implement the plan provided in context. The plan is in the issue body
    under `## plan` — it includes numbered steps, architecture, risks, and
    verification guidance.

    **Build only.** Do not run tests, linters, formatters, or any
    verification command. Do not run `bundle exec rake test`.
    Do run `bundle install` as needed — that is a build step.
    Sensors will verify correctness after you finish.

    Execute every step in the plan. Write code, create files, edit files.
    Follow the plan's architecture, approach, and steps precisely. If you
    encounter ambiguity, make a reasoned choice and note it in your summary.

    When you finish implementing, provide a brief summary of:
    - What you built (files created/modified).
    - Any decisions that diverged from the plan and why.
    - Any steps you could not complete and why.
    """,
    context_inputs: [:plan],
    messages: [
      %{user: "Implement the plan. Build only — do not run tests or verification. When finished, output a brief summary of what you built.", output_key: :implementation_summary},
      %{user: "Emit a short, descriptive git branch name derived from the plan (follow the convention type/short-slug, e.g., feat/add-calculator). Output only the branch name — no quotes, markdown, or commentary.", output_key: :branch_name},
      %{user: "Emit a concise one-line PR title for this implementation (max ~80 chars). Output only the title text — no quotes, markdown, or commentary.", output_key: :pr_title}
    ],
    sensors: ["bundle exec rake test"],
    retry_on: :sensors,
    max_retries: 3,
    tools: [
      "read_file",
      "read_range",
      "find_files",
      "search_files",
      "list_directory",
      "write_file",
      "edit_file",
      "run_shell",
      "explore_files",
      "consult_expert",
      "consult_elder",
      "web_search",
      "ask_user"
    ]
  },
  # --- Phase 3: Review ---
  %{
    name: :review,
    system_prompt: """
    You review the plan and its implementation for correctness and quality.
    Read the implementation files to understand what was built; compare against
    the plan. Check for:

    - **Plan alignment** — does the implementation match every requirement?
      Flag missing features, scope mismatches, and unrequested additions.
    - **Edge cases** — are boundary conditions, error states, and failure modes
      handled?
    - **Code quality** — clarity, duplication, naming, structure. Is the code
      easy to understand and maintain?
    - **Simplification** — can anything be made simpler without losing
      functionality?
    - **Underspecification** — did the plan leave gaps that the implementation
      had to fill? Are those choices reasonable?

    Make changes to fix any issues you find. **Build only.** Do not run tests,
    linters, formatters, or any verification command. Sensors will
    verify after you finish.

    Output a summary of your review: what you checked, what you found, and what
    you changed (with file paths). If the implementation is already strong, say
    so and list only minor polish you applied.
    """,
    context_inputs: [:plan, :implementation_summary, :pr_title],
    messages: [
      %{user: "Review the implementation against the plan. Make fixes as needed (build only). Output a review summary.", output_key: :comment_body},
      %{user: "If the review changed the PR's scope or direction, emit a revised PR title (max ~80 chars). Otherwise repeat the original title. Output only the title text — no quotes, markdown, or commentary.", output_key: :revised_pr_title}
    ],
    sensors: ["bundle exec rake test"],
    retry_on: :sensors,
    max_retries: 3,
    tools: [
      "read_file",
      "read_range",
      "find_files",
      "search_files",
      "list_directory",
      "write_file",
      "edit_file",
      "run_shell",
      "explore_files",
      "consult_expert",
      "consult_elder",
      "web_search",
      "ask_user"
    ]
  },
  # --- Phase 4: Create Pull Request (deterministic) ---
  %{
    name: :create_pr,
    run: {Retcon.Workflow.GitHub, :create_pr, []},
    context_inputs: [:branch_name, :revised_pr_title, :pr_title, :plan, :implementation_summary, :issue_ref, :issue_title, :task]
  },
  # --- Phase 5: Post PR comment (deterministic) ---
  %{
    name: :comment_pr,
    run: {Retcon.Workflow.GitHub, :comment_pr, []},
    context_inputs: [:pr_url, :comment_body]
  }
]
