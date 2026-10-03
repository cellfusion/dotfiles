# Guides and manuals: help readers complete the actual task

## Purpose and evidence boundary

A guide may be read from start to finish by a beginner or opened at one section by a returning user. Make the needed procedure and context findable for both uses where applicable.

**Source guidance:** The [2022 public-writing recommendation](../sources.md) supports reader-oriented organization, clear terminology, accurate content, and useful headings. The guide patterns below are editorial heuristics; they do not require every guide to contain a glossary, narrative introduction, or identical section structure.

## Information to consider

- Intended readers, necessary knowledge, access, and supported environment.
- What the reader can accomplish, and important exclusions.
- Preconditions, steps, expected results, and relevant warnings.
- Explanations of unfamiliar terms at useful locations.
- Troubleshooting and an actual support route, when supplied.
- Version or update date when it helps distinguish current instructions.

Include only applicable elements supported by the material. Do not invent a support channel, policy, requirement, verification claim, or update date. Missing procedural facts may need confirmation before a usable guide can be completed.

## Choose structure by task

- **Tutorial:** explain a sequence for a beginner, with reasons where useful.
- **Task procedure:** make the goal, preconditions, operations, and outcomes clear.
- **Goal-based lookup:** group independent tasks by what the reader wants to do.
- **Reference:** use stable entries or tables for parameters, limits, and meanings.
- **Troubleshooting:** connect supported symptoms to confirmed checks and actions.

These patterns can coexist. Consistent step wording and reference entries can help retrieval; do not disrupt them because repeated structure triggers a tool. Explanations need not alternate with every step. Keep important warnings before the affected operation, not hidden in an optional aside.

Use headings that name the task or answer. A familiar label such as 「申請方法」 can work well. Avoid vague cross-references such as “see the next chapter” when a specific section name would help, but do not force different wording for every link.

## Accuracy and modality

Distinguish tested behavior, source-documented behavior, expected behavior, and an unverified assumption. Do not label a plausible invented instruction as “expected” and present it as an adequate procedure. If essential behavior cannot be established, identify the precise gap and finish supported content.

Keep UI labels, commands, settings, and output exact. Do not imply that an operation is safe, reversible, automatic, or required without support. A shorter sentence must not erase a warning, condition, permission, or dependency.

## Before/after using the supplied procedure

**Before**

> ## 利用方法
> 領収書をアップロードし、勘定科目を選択し、申請ボタンを押してください。承認されると自動的に振り込まれます。

**After**

> ## 領収書をアップロードして申請する
> 1. 領収書をアップロードしてください。
> 2. 勘定科目を選択してください。
> 3. 申請ボタンを押してください。
>
> 承認されると、自動的に振り込まれます。

**Preservation invariants:** the same three operations, their order, polite instructions, and the stated approval-conditioned automatic payment. The edit does not verify the workflow.

**Do not add:** one application per receipt, a prohibition on combining receipts, an accounting rationale, a three-day payment schedule, a five-day month-end delay, or an invented exception form. The before text contains none of these.

If the claimed automatic payment is uncertain, flag the need for confirmation outside the faithful rewrite rather than replacing it with an invented schedule.

## Goal-based headings

A heading can expose a supported answer:

- Supplied fact: 「差し戻し理由は通知メールに記載される」.
- Useful heading: 「申請が差し戻されたら、通知メールで理由を確認する」.

Without the supplied fact, the heading cannot assert where the reason appears. Do not add an apparent solution merely because it makes the guide more useful.

## Maintenance and final review

When updating a guide, revise stale instructions and affected references rather than restyling unrelated chapters. Keep dates and version claims factual. Reader questions can identify gaps, but do not claim that users were consulted or a procedure was exercised if that did not happen.

Can a reader complete the supported task from the relevant section? Are necessary prerequisites and warnings available there? Do repeated explanations aid comprehension or simply pad the guide? Are terminology, operation order, and conditions preserved? See `../eval-rubric.md` for qualitative review; a numeric threshold is not a usability check.
