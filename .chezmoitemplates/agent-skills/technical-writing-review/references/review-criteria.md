# Technical writing criteria

Evaluate whether this reader can understand and act on this text. These are contextual criteria,
not a mandatory document template. Respect existing project terminology and writing conventions.

## Readability and Japanese

- Put the conclusion where the reader needs it; usually before supporting details.
- Keep paragraphs focused on one idea. Separate tangled reasons, exceptions, and requests.
- Check Japanese modifier attachment, conditional clauses, double negatives, parallel lists,
  and ambiguous referents such as 「これ」「対応」「改善」. Cite the actual ambiguity.
- Explain unfamiliar abbreviations when the intended reader needs them. Preserve API names,
  code identifiers, official UI labels, and quotations. Unify terms only for the same concept.
- Judge reading difficulty, not a fixed character/word count. Do not transfer English word limits
  to Japanese. Natural passive voice, omitted subjects, and heading fragments can be correct.
- Do not force all text into ですます, add 「あなた」, or replace technical terms with casual words.
  Avoid excessive politeness, blame, and needless abruptness without flattening the author's tone.

## Enough explanation

- PR description: as relevant, problem/motivation, what changes, before/after behavior, affected
  scope, prerequisites, compatibility constraints, verified and unverified parts, related issue,
  and review focus. Never require every heading for every change.
- Comment: for a finding, target/reason/request; for a question, what decision is needed;
  for an answer, conclusion and necessary support. Use the surrounding thread's known context.
- Explanation/instructions: reader prerequisites, goal, causal links or ordered actions,
  useful examples, limitations, and exceptions that affect use.
- Distinguish supplied facts, claims needing evidence, and unavailable context. Do not invent
  implementation intent, benchmarks, tests, safety, or compatibility guarantees. An unsupported
  claim is a confirmation question, not proof it is false. Do not execute code to validate prose.
- Point to the missing information and the decision it prevents. 「説明を追加してください」 alone
  is not actionable. Do not request irrelevant background or repeat already accessible context.

## Structure and visuals

Choose the simplest representation that materially helps understanding:
- independent items: bullets; straightforward ordered steps: numbered list;
- comparable alternatives or before/after conditions on shared axes: table;
- meaningful branches: flowchart; interactions over time: sequence diagram;
- states and transition conditions: state diagram; ownership/dependencies/boundaries: component diagram;
- visual UI change: relevant screenshot with private material excluded.

Do not propose a diagram for a simple change or two straightforward steps. Do not convert code,
logs, or terminal output into images. A diagram cannot substitute for missing facts.
A visual finding must identify the reader's comprehension problem, representation type, confirmed
minimum elements, and insertion point. If entities/arrows/conditions are unknown, ask for them
rather than generating a speculative diagram. Avoid adding unrelated components.
For GitHub, Mermaid fenced blocks are a candidate, not a guarantee that every syntax version works.
Include a prose summary and accessible labels; color or spatial position must not be the sole
carrier of meaning. Diagram syntax validation does not prove GitHub rendering was observed.

## Finding contract

Each child returns:
- role: readability / explanation / visuals;
- draft identity: the snapshot label supplied by the parent;
- findings (empty is valid), each with:
  - ID unique within that role;
  - category: 修正推奨 / 確認が必要 / 任意改善;
  - location and short exact quote;
  - reader impact and evidence from draft/context;
  - concrete suggested edit or question;
  - meaning-change risk and any facts required before applying the suggestion;
  - for visuals, type, minimum elements, and insertion point;
- limitations: unavailable context and what this lens did not establish.

Do not emit a PASS/FAIL on code correctness. Do not return an unsolicited full rewrite, require a
minimum number of findings, or elevate personal preference to a defect.

## Sources and limits

These sources inform the criteria; they are not universal Japanese rules:
- [Google: paragraphs](https://developers.google.com/style/paragraph-structure)
- [Google: clear, translatable text](https://developers.google.com/style/translation)
- [Google: tone](https://developers.google.com/style/tone)
- [Google: accessibility](https://developers.google.com/style/accessibility)
- [Google: images](https://developers.google.com/style/images)
- [Google: tables](https://developers.google.com/style/tables)
- [Microsoft Japanese localization guide](https://aka.ms/japanese-styleguide): brand/localization
  guidance; use audience-sensitive Japanese advice, not automatic vocabulary substitutions.
- [GitHub: helping reviewers](https://docs.github.com/en/pull-requests/concepts/helping-others-review-your-changes)
- [GitHub: diagrams](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)
