---
name: experiment-to-article
description: >-
  Declare an experiment's objective, delegate execution and independent review,
  preserve evidence and decisions, and turn the findings into a traceable article.
  Use for code behavior checks, performance comparisons, tool comparisons,
  configuration or implementation evaluations, resuming experiments, and writing
  articles from experimental evidence. Articles default to Japanese.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# From Experiments to an Article

The parent agent owns direction, records, acceptance decisions, and the article. Delegate experiments to a child agent and review to a different child agent. Judge whether the experiment supports its conclusions, not whether it produced the desired result.

## Operations and Responsibilities

Interpret natural-language requests as start, continue, status, write article, or interrupt. Do not ask again for information already available. If a continuation request does not identify a run, inspect candidates under `~/docs/experiments/`; ask the user to select when multiple candidates exist.

- **Parent:** plan, assign work, reserve IDs, coordinate resources, inspect evidence, resolve findings, accept or reject results, maintain records, and write the article.
- **Experiment worker:** create code within the assigned scope, execute it, preserve evidence, and report results. Do not change the objective or decision criteria.
- **Reviewer:** read the plan, code, original evidence, and report; assess methods and interpretation. Never review a trial you executed. Remain read-only by default. If additional execution is necessary, return its reason and procedure to the parent.

Use separate agents and separate contexts to ensure independence; different models are not required. Use only child-agent capabilities actually available in the runtime. If unavailable, report the limitation and ask the user before switching to solo execution. Never pretend that independent delegation occurred.

This skill does not authorize publication, production integration, commits, pushes, or `chezmoi apply`. Do not overwrite or delete existing user files. Confirm permissions and costs before experiments involving external services, secrets, or production data.

## Storage and Identifiers

The source of truth is `~/docs/experiments/<run-id>/`, not conversation history. Show its absolute path at the start.

The parent automatically generates a run ID as `YYYYMMDD-HHMMSS-short-topic` using local time. Derive the topic from the objective using lowercase ASCII letters, digits, and hyphens; use `experiment` if empty. On collision, append `-02`, `-03`, and so on. Confirm exclusive creation of the new directory before using it; never reuse an existing directory for a new run. Keep the ID unchanged when resuming.

Number experiments from `E001` and trials within each experiment from `A01`. A full trial ID is `E001-A01`. Only the parent allocates and reserves IDs, recording them in status before dispatch. Do not treat the displayed digit width as a limit. On resume, inspect the highest numbers in both directories and records; never reuse reserved or interrupted IDs.

Allow only one active parent per run. Before allocating IDs, dispatching, or changing records, exclusively create a `.parent-lock/` directory and record the parent identity, acquisition timestamp, and owned child references in it. If it already exists, do not mutate the run: establish whether its owner is active, request an explicit handoff if needed, and preserve evidence when ownership is unknown. Never infer that a claim is stale from elapsed time alone. Release only your own claim after recording a safe stopping or handoff state; remove a previous claim only after its owner has relinquished it or the user has authorized recovery and outstanding children have been accounted for.

Use a new trial for corrections or reruns of the same question, and a new experiment for a different question. If decision criteria change, increment the plan version, record the reason, and distinguish results evaluated under different criteria.

```text
~/docs/experiments/<run-id>/
├── plan.md
├── journal.md
├── status.md
├── experiments/
│   └── E001/
│       ├── request.md
│       └── A01/
│           ├── report.md
│           ├── review.md
│           ├── code/
│           └── evidence/
└── article.md
```

Prefer relative links. Retain plans, failed trials, reviews, and original evidence after completion. Append corrections without deleting earlier results. The article and status may be updated, but record reasons for changed conclusions in the journal. Avoid collecting secrets, redact necessary log fields before saving, and exclude private information from publishable articles.

Use timestamps with time zones. As applicable, include the run ID, experiment/trial IDs, plan version, assigned role and actual agent identity, and evidence paths in each event. These experiment records are this skill's audit trail; do not duplicate full conversations or secrets into another audit log.

## 1. Declare the Objective and Plan

Fill in the following plan template and present its key points before execution. Do not require renewed approval of an already agreed objective. Ask only about missing information that changes results, scope, safety, permissions, or costs. Label safe provisional assumptions explicitly.

```markdown
# Experiment Plan
- Run ID / storage path / start timestamp:
- Plan version: 1
- Objective: the decision this investigation should inform
- Question: a question answerable through observation
- Hypothesis: unset for exploratory work if appropriate
- In scope / out of scope: comparison targets, versions, exclusions
- Method: controls, fixed and changed conditions, measurement and observation steps
- Decision criteria: which results justify which conclusions
- Environment: OS, tool versions, code revision or identity
- Constraints / prohibited operations:
- Limits: experiment count, total trials, corrections per experiment, overall and per-trial runtime, reviewer wait time and replacements, article correction passes
- Cost ceiling: required when using paid resources
- Article: audience, purpose, language (default: Japanese technical article)
- Provisional assumptions / unresolved questions:
## Revision History
Timestamp / version / change / reason / affected trials
```

Unless specified otherwise, use provisional limits for reversible local work: 5 experiments, 10 total trials, 2 corrections per experiment, 60 minutes overall, 10 minutes per trial, 5 minutes per reviewer wait, at most 1 replacement reviewer per review stage, and 2 article correction passes. Declare these limits at the start. Overall elapsed active-work time and cost include experiments, reviews, reviewer replacements, and article work; preserve accumulated usage across interruption and resume. Count parallel trials toward the total. Set suitable limits before starting a plan expected to need more time. Do not use paid resources until pricing and a cost ceiling are confirmed. Never extend limits automatically.

## 2. Assign and Execute Experiments

Normally assign one question per task. Parallelize only independent experiments. Serialize performance measurements and experiments sharing a device, code, files, or services whenever they could interfere. Save experimental code in the trial's `code/` directory. If a repository is needed, use an isolated workspace and record its path, base revision, owner, and allowed changes. Preserve the differences or identifiers needed for reproduction in the run directory.

Save the following fields in `request.md`. Also record each trial's specific assignment at the beginning of its `report.md`.

```markdown
# Experiment Assignment
- Experiment ID / question / hypothesis:
- Plan version / decision criteria:
- Fixed conditions / changed conditions / controls:
- Procedure / required repetitions:
- Workspace / allowed changes / prohibited operations:
- Evidence to preserve:
- Trial runtime limit / stop conditions:
- Report destination: report.md in the trial directory
```

Give the child the plan, assignment, evidence destination, and acceptance criteria. Use a fresh context for each trial; include earlier finding IDs and required corrections when applicable. Execute commands needed for the experiment, but do not request unrelated builds or full test suites.

After execution, the worker returns the following report. Preserve reports and evidence even on execution failure or budget exhaustion.

```markdown
# Trial Report E001-A01
- State: completed / execution failed / interrupted
- Criterion outcome: met / not met / not evaluated (separate from execution state and review verdict)
- Worker / start and end timestamps / plan version:
- Current assignment / changes from the previous trial / addressed finding IDs:
## Work Performed
Actual operations, deviations from the plan, and their reasons
## Reproduction
Environment, dependencies, code identity, working directory, exact commands, exit codes
## Observations
Actual output, measurements, and state; relative evidence links; units, sample counts, and variability for measurements
## Interpretation
What the observations support; explicitly label inference
## Limitations and Unverified Items
Errors, missing data, environmental constraints, excluded data and reasons
```

Statements such as "executed" or "works" are insufficient for completion. Preserve output or state that answers the question. For performance comparisons, align controls and measurement conditions, predeclare necessary repetitions, and never select only favorable measurements.

A nonzero command exit code does not by itself determine scientific validity. Record whether it is an expected negative observation, a failed implementation criterion, or an infrastructure failure, with evidence. A completed execution is not proof that its implementation is correct.

## 3. Independent Review and Parent Decision

Give a different child the plan, assignment, report, code, and original evidence. Do not review summaries alone. The reviewer checks:

- Fit to the question, comparison conditions, code correctness, and measurement methods.
- Agreement between evidence and report, reproducibility, and necessary controls or repetitions.
- Separation of observation from interpretation, overgeneralization, unsupported causation, and hidden failures or counterexamples.

```markdown
# Trial Review E001-A01
- Reviewer / timestamp / evidence inspected:
- Verdict: valid / correction required / inconclusive
## Findings
Finding ID (e.g. E001-A01-F01) / severity / evidence path / issue / effect on conclusions / smallest correction
## Additional Verification
Required rerun and reason, or no additional verification
```

- **Valid:** methods, evidence, and interpretation are sound. Results contradicting the hypothesis can be accepted.
- **Correction required:** methods, implementation, or evidence are defective. Specify the reason and correction, then rerun under a new trial ID.
- **Inconclusive:** the experiment is valid but insufficient to answer the question. Add an experiment or record the limitation.

The parent inspects evidence and review, then appends acceptance or rejection, reasons, finding dispositions, and next actions to the journal. Never accept a result with unresolved major findings. If rejecting a finding, preserve the evidence and rationale. Reviewers advise; the parent owns the final decision.

If a reviewer times out, fails, or cannot inspect required evidence, record the review as unavailable, not valid. Account for outstanding children before using the bounded replacement allowance. If no independent verdict is obtainable within the limits, keep the trial awaiting review, do not adopt it, and report the blocker. Do not replace independent review with the worker's or parent's self-review.

Even repetitions under identical conditions require a reason, such as assessing variability. Never repeat until the desired result appears. Do not overwrite earlier trials. For every finding, record the resolving trial, deferral, or reason for rejection.

## 4. Record Progress, Stop, and Resume

Keep the journal chronological and append-only.

```markdown
## Timestamp — E001-A01
- Work performed:
- Result:
- Review: verdict and finding IDs
- Decision: acceptance, rationale, finding dispositions
- Evidence: relative links
- Next: additional experiment / article / interruption and reason
```

Maintain the following status fields, updating them after experiment completion, review completion, decisions, and interruptions.

```markdown
# Current Status
- Run ID / storage path / plan version:
- Investigation state: in progress / interrupted / conclusion available / inconclusive / unable to execute
- Article state: not started / drafting / under review / complete
- Experiments and trials: IDs, questions, assignees, reserved / running / awaiting review / decided / interrupted
- Limits and usage: trial count, corrections, cumulative runtime, cost
- Accepted results / unresolved findings:
- Next action / resume conditions:
- Workspaces and external resources: owners, running state, restoration and cleanup state
```

Stop experiments when the question is sufficiently answered, any limit is reached, required environment or permissions are unavailable, further work requires a scope change, or recurring problems lack a new resolution rationale. Distinguish conclusions, inconclusive results, and inability to execute; organize findings and limitations for an article. Preserve records and ask the user when extending limits or permissions is necessary.

The overall time or cost ceiling also stops substantive review and article work. Save the stopping state and evidence references; leave the article incomplete or awaiting review if its independent review is unfinished. Minimal safe shutdown and status reporting are still required. Limit exhaustion never waives the review requirement.

On interruption, safely stop owned execution and record incomplete trials and next steps. On resume, establish exclusive parent ownership first, then read the plan, status, journal, and unresolved reviews; check code or environment changes and remaining limits. Never mark interrupted trials complete. Preserve their evidence and rerun under a new trial ID. Check for still-running children before dispatching replacements.

Safely stop or restore only temporary resources created by this run; do not delete user workspaces. Reproduction code, measurement data, and reviews are not disposable temporary resources.

## 5. Write the Article and Check Its Evidence

The parent writes `article.md`. Explain findings in the order useful to readers rather than pasting the journal. For Japanese articles, use concise, natural prose and distinguish facts, interpretation, and unverified claims.

The default structure covers objective, conclusion and applicability, environment/methods/criteria, major experiments and results, failures and reasons for changing direction, interpretation, limitations, reproduction, and evidence references. Retain failures, counterexamples, and exclusion reasons that affect the conclusion. Link major values and claims to trial IDs and evidence.

Assign final review of the article and evidence to a child other than the experiment worker. Reusing the trial reviewer is allowed. Check values and conditions, support for claims, measured versus inferred statements, omitted counterexamples, generalization, reproduction information, and secret leakage. Save findings with IDs, evidence, and corrections in `article-review.md`; record the parent's dispositions in the journal.

Fix writing issues in the article; address missing evidence through additional experiments within remaining limits. If additional execution is unavailable, narrow claims and explicitly mark unverified items. Mark the article complete only after major findings are resolved or dispositioned with evidence and revised claims are consistent with the evidence. An inconclusive or unexecutable investigation can still produce a complete article that explains its limits.

The final report briefly states the conclusion, investigation and article states separately, absolute article path, record location, experiment/trial counts, important limitations, and resource restoration state. Do not equate article completion with a confirmed hypothesis or production adoption.

## Usage Examples

- Start: "Use experiment-to-article to compare response times of implementations A and B, then write a Japanese article. The objective is to decide which implementation to adopt."
- Continue: "Resume the investigation in ~/docs/experiments/<run-id>/ using experiment-to-article."
- Status: "Show what this investigation established and which findings remain unresolved."
- Write article: "Do not run more experiments; write an article from the current evidence and limitations."
- Interrupt: "Stop execution and preserve enough context to resume next time."

Prefer explicit skill selection. Automatic selection from the description depends on the runtime and is not guaranteed.
