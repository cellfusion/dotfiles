---
name: natural-japanese
description: >-
  Write, revise, and review clear, idiomatic Japanese for the intended reader and genre.
  Use for Japanese meeting minutes, reports, proposals, guides, email, slide copy,
  articles, essays, translation-like phrasing, awkward syntax, and requests to make
  writing less formulaic or more natural. Also use for style-profile requests and
  critique without rewriting. Do not infer AI authorship from writing style. Markdown
  formatting or technical document architecture alone is outside this skill.
license: MIT
argument-hint: "[write|score] [quick|full|exp] [file or request]"
---

# Natural Japanese

Improve what the reader can understand, not how successfully the text imitates a
stereotype of human writing. Preserve the author's meaning and voice. Instructions
and explanations in this skill are English; Japanese is used for examples and
language patterns. The requested deliverable remains Japanese unless specified otherwise.

## Non-negotiable priorities

1. **Fidelity:** preserve facts, attribution, numbers, dates, conditions, negation,
   obligation, permission, uncertainty, and the distinction between proposals and decisions.
2. **Reader fit:** choose vocabulary, detail, politeness, and structure for the audience,
   purpose, genre, and any supplied style samples.
3. **Comprehension:** make agents, predicates, referents, modifier scope, and logical
   relationships recoverable without rereading.
4. **Economy:** remove material only when it adds no information or useful tone.
   A longer but clearer sentence or list can be better than a shorter ambiguous one.

Never invent evidence, deadlines, participant responses, personal experience, or
emotions to make a passage concrete or warm. If the source is ambiguous, preserve
that ambiguity or identify the question; do not silently decide what it meant.
A legal quotation, product name, code identifier, or agreed technical term is not
an invitation to paraphrase. Distinguish faithful quotations from summaries.

## Invocation and depth

- `/natural-japanese [quick|full] <target>`: write or revise as requested.
- `/natural-japanese write [quick|full] <brief>`: draft from supplied material.
- `/natural-japanese score [quick|full|exp] <target>`: critique only; read
  `references/diagnose.md` first. Do not modify the target. A requested score is an
  explicitly subjective editorial assessment, never an authorship probability.

Natural-language requests have the same semantics. **Quick** is the default for
routine writing: establish the brief, draft/revise, review meaning and readability,
then return the deliverable. **Full** applies when requested or when stakes warrant
independent scrutiny: add source-to-draft fidelity review, genre/structure review,
and sentence-level review using `references/eval-rubric.md`. Use independent
reviewers for substantial full-mode documents when available; keep one integration
owner and report unavailable review capabilities honestly. Do not promise execution
times or require a particular model/effort setting.

**Exp** adds the optional embedding experiment to a diagnostic review. It is not a
better AI detector. Do not install dependencies or download models without explicit
permission; the experiment depends on torch and sentence-transformers and may
require a large download. A missing tool does not prevent manual revision.

Some model repositories require executing their Python code. Remote-code trust is
disabled by default; use `--trust-remote-code` only after explicit approval of that
code execution for the selected repository. Download permission alone is not code
execution permission.

## 1. Establish the brief and evidence

Use the request and material to determine reader, purpose, genre, desired register,
and scope of permitted changes. Ask only when an unresolved choice materially
changes the deliverable. For revision, list the propositions that must survive,
especially high-risk conditions and commitments. For drafting, separate provided
facts, sourced facts, assumptions, and missing information.

Read the relevant genre reference, not the entire library:

| Document | Reference |
| --- | --- |
| Meeting minutes / transcript summary | `references/doctypes/minutes.md` |
| Research or analysis report | `references/doctypes/report.md` |
| Guide / manual | `references/doctypes/guide.md` |
| Research memo / proposal | `references/doctypes/memo.md` |
| Slide copy / outline | `references/doctypes/slide.md` |

For email, identify recipient, request, required action, and any actual deadline;
keep courteous framing when it serves the relationship. For articles and essays,
preserve the chosen narrative perspective and pacing; do not force business-report
structure onto them. Research only facts needed for the task and cite external
sources. Do not fill source gaps with plausible specifics.

Use a supplied style profile if relevant. Read samples for tendencies rather than
copying every quirk. Create or persist `style-profile.md` only when requested,
using `assets/style-profile-template.md`. Record user-specific preferences with
scope and provenance, not as universal rules of Japanese.

## 2. Draft or revise in Japanese

Use `references/writing-constitution.md` for detailed guidance and
`references/readability-principles.md` for difficult sentences. Apply these defaults
with context, not as lexical prohibitions:

- Put the information the reader needs where they expect it. An actionable email
  often leads with its request; a narrative need not reveal its ending first.
- Keep modifiers close to their targets. Check the topic and predicate together.
  Add an omitted subject only when the reader cannot recover it reliably.
- Split a sentence when independent claims, conditions, or viewpoints obscure
  their relationship. Preserve causal links and qualification across the split.
- Choose ordinary verbs when heavy nominalizations add nothing. Preserve technical
  precision and meaningful modality; ability is not the same as a factual assertion.
- Use punctuation to clarify grouping. Do not insert commas at fixed intervals.
- Explain unfamiliar terms at first useful mention, without defining vocabulary
  already familiar to the intended reader. Avoid mechanical synonym substitution.
- Keep register coherent. Polite language is not inherently redundant; excessive
  deference can obscure who is requesting or doing what.
- Use headings, lists, tables, or paragraphs according to the reader's task.
  Parallel checklists and ordered procedures are useful, not inherently unnatural.
- Remove repeated conclusions and generic padding when they add no distinction.
  Do not deliberately randomize sentence lengths or section sizes.

Examples of meaning-preserving edits:

> Before: 本機能を利用することによって、作業時間を短縮することができます。
> After: この機能を使うと、作業時間を短縮できます。

The edit keeps a claim of capability; it does not assert measured savings.

> Before: 部長が昨日提出した資料を確認した。
> Review: Did the department head submit the material, or review it?
> If the source confirms that the department head submitted and you reviewed:
> 部長が昨日提出した資料を、私が確認した。
> If the source confirms that the department head reviewed material submitted yesterday:
> 昨日提出された資料を、部長が確認した。

The alternatives require source confirmation; neither is an unconditional rewrite.

> Source: 導入案については、次回の会議で検討を行う。
> Acceptable: 導入案は次回の会議で検討する。
> Unacceptable: 次回から導入することを決定した。

## 3. Inspect; use tools as review aids

Resolve `SKILL_DIR` to the directory containing this file. Resolve `DOCUMENT` to
an absolute target path so commands work from any project directory. Where `uv`
and the script dependencies are cached, use offline execution:

```sh
uv run --offline "$SKILL_DIR/scripts/lint.py" --json "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/lint.py" --reading-load "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/outline.py" "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/terms.py" "$DOCUMENT"
```

If dependencies are not cached, use manual review or obtain permission before
installing packages. Do not drop `--offline` merely to make the command succeed.

Use `--genre essay|tech|business` when applicable. These are heuristic profiles,
not validated guarantees for a genre. For a quick revision, lint and direct reading
usually suffice; for full review, inspect reading load, outline, and relevant terms.
If execution is unavailable, use `references/manual-checklist.md` and disclose the
omitted automated check. Do not create a file merely to lint a one-sentence chat
reply when direct review is adequate.

Findings identify candidates to inspect, not errors to remove automatically.
Read the relevant portions of `references/revision-guide.md`,
`references/forbidden-patterns.md`, `references/translationese.md`,
`references/readability-antipatterns.md`, or `references/genre-notes.md` when needed.
The historical filename `forbidden-patterns.md` does not make its entries bans.

Lint's finding severities are rule labels, not measured linguistic harm. A successful
lint exit is not a quality verdict. Reading-load findings are a separate review
lane and are not included in baseline comparison. `terms.py` produces candidate
terms, not proof that a term is unexplained. `outline.py` cannot verify reasoning.
The optional `semantic.py --json` measures embedding-based topic variation; it
cannot establish authorship, truth, or Japanese naturalness.

## 4. Review and reconcile

Keep a compact internal decision ledger for substantive issues: source location,
reader impact, proposed change, and either accepted or retained with reason.
Do not expose a large ledger unless requested.

Review in this order:

1. **Fidelity:** compare source and revision for missing/added claims, changed agency,
   negation scope, condition scope, numbers, attribution, and confidence.
2. **Purpose and structure:** can the reader find the requested answer or action?
   Does each paragraph advance it? Are proposals, decisions, and unresolved issues
   separated? Do headings and lists help this particular document?
3. **Sentence comprehension:** check modifier attachment, topic/predicate relation,
   referents, parallelism, punctuation, term consistency, and register.
4. **Voice and economy:** remove empty repetition without erasing useful courtesy,
   emphasis, authorial style, or intentional rhythm.

For full review, give independent reviewers the source as well as the draft; a
review of the draft alone cannot establish fidelity. Require quoted passages,
reader impact, and concrete alternatives. The integration owner adjudicates
conflicts; agreement between reviewers is not evidence of truth.

Revise only where the change solves an identified problem. Rerun affected checks
if automated findings guided substantial changes. `lint.py --baseline <previous-json>`
can classify resolved/new/persisting findings, but moved or rewritten passages may
not match reliably. Do not chase zero findings or repeatedly rewrite correct text
to raise a score. If revisions oscillate, return to the source and keep the clearer
faithful version. Stop when substantive defects are resolved, retained findings
have contextual reasons, and a final source comparison finds no meaning drift.

## 5. Deliver

Return the requested Japanese text, or the requested critique without rewriting.
Explain only consequential edits, unresolved ambiguity, and verification limits.
For full reviews, use the qualitative acceptance checks in `references/eval-rubric.md`;
no self-awarded numerical threshold establishes quality. Never claim that the
result is human-written or cannot be recognized as AI-assisted.

Keep temporary lint outputs and ledgers outside the user's project where possible.
Remove only temporary files created by this run; preserve supplied files, review
artifacts the user requested, and existing backups. More worked examples are in
`references/examples.md`.
