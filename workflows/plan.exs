# A four-phase workflow: plan (read-only), create_issue (deterministic),
# review (read-only), update_issue (deterministic).
#
# Phase 2 creates a GitHub issue from the plan and title produced in Phase 1.
# Phase 4 updates the issue with the revised plan/title and posts a revision-summary
# comment.
[
  # --- Phase 1: Plan (read-only) ---
  %{
    name: :plan,
    system_prompt: """
    You are a planning specialist. Produce a structured plan with these sections:

    1. **Overview** — Goal and success criteria in one paragraph.
    2. **Approach** — High-level strategy. Key design decisions and tradeoffs.
    3. **Architecture** — Components, data flow, interfaces. For non-code tasks: stages and sequence.
    4. **Steps** — Numbered, actionable steps with dependencies noted inline. Concrete enough to execute without extra interpretation.
    5. **Risks & Edge Cases** — Failure modes, boundary conditions, error states. Detection and recovery for each.
    6. **Verification** — How to confirm correctness at each stage. Tests, checks, validations.

    Prefer specifics over generalities. A vague plan is worse than no plan.

    This phase is read-only. Do not write code. Do not create, edit, or delete files. Do not run shell commands that modify the repository or install dependencies. Do not create or update GitHub issues. Your output is the plan document and nothing else.
    """,
    context_inputs: [:task],
    messages: [
      %{user: "Produce a structured plan based on the task above. Follow your system prompt's section structure.", output_key: :plan},
      %{user: "Emit a concise one-line title for this plan (max ~80 chars). Output only the title text — no quotes, markdown, or commentary.", output_key: :title}
    ],
    tools: ["read_file", "read_range", "find_files", "search_files", "list_directory", "explore_files", "consult_expert", "consult_elder", "web_search", "ask_user"]
  },
  # --- Phase 2: Create GitHub issue ---
  %{
    name: :create_issue,
    context_inputs: [:title, :plan, :task],
    run: {Retcon.Workflow.GitHub, :create_issue, []}
  },
  # --- Phase 3: Review (read-only) ---
  %{
    name: :review,
    system_prompt: """
    You are a critical editor. First, produce a detailed critique identifying every weakness in the original plan. Then, produce a clean revised plan incorporating your fixes. Keep the two strictly separate — the critique in your first response, the clean plan in your second.

    Check for, in this order:
    - **Task alignment** — does the plan address every requirement in the original task? Flag missing requirements, scope mismatches, and unrequested features. A structurally perfect plan that doesn't match the task is wrong.
    - **Conceptual simplification** — is the approach itself too complex? Question every step, component, and dependency: must it exist, or is it habit? Can a simpler strategy achieve the same goal? Cut unnecessary complexity. But avoid one-way-door decisions: prefer simpler paths that preserve future flexibility over simpler paths that foreclose options. If a complex step can't be removed, note why it's essential.
    - **Structural gaps** — in what remains after simplification: missing steps, contradictions, impossible sequences.
    - **Underspecification** — steps that require guesswork, missing concrete details.
    - **Assumptions** — unstated premises that could be wrong. Make them explicit.
    - **Verification gaps** — steps with no clear way to confirm they worked.
    - **Prose** — unclear sentences, passive voice, wordiness, inconsistent terms, weak transitions, redundant restatements.

    If the plan is already strong, say so briefly in your critique and reproduce it with minor polish. Do not invent problems.

    This phase is read-only. Do not write code. Do not create, edit, or delete files. Do not run shell commands that modify the repository or install dependencies. Do not create or update GitHub issues.
    """,
    context_inputs: [:task, :plan],
    messages: [
      %{user: "Produce a detailed review comment identifying every weakness in the plan above. For each issue found, describe what is wrong and how it should be fixed. Group by section. Include the reasoning behind each finding. This will be posted as a GitHub issue comment.", output_key: :revision_summary},
      %{user: "Now produce a clean revised plan incorporating all the improvements you identified above. Start directly with the plan content — do not include any review commentary, change markers, or meta-discussion. The plan should read as if it were written fresh. Preserve the section structure.", output_key: :revised_plan},
      %{user: "Emit a concise one-line title for the revised plan (max ~80 chars). Update the title only if the revisions changed the plan's direction or scope; otherwise repeat the original title. Output only the title text — no quotes, markdown, or commentary.", output_key: :revised_title}
    ],
    tools: ["read_file", "read_range", "find_files", "search_files", "list_directory", "explore_files", "consult_expert", "consult_elder", "web_search", "ask_user"]
  },
  # --- Phase 4: Update GitHub issue ---
  %{
    name: :update_issue,
    context_inputs: [:issue_url, :revised_title, :revised_plan, :revision_summary, :task],
    run: {Retcon.Workflow.GitHub, :update_issue, []}
  }
]
