# Clarity repair catalog

These are editorial review questions, not universal defects, authorship markers, or a validated ranking of cognitive load. Apply only the entries relevant to a passage. [Sources](sources.md) provide primary guidance for accuracy, clause relations, audience-aware terminology, and document purpose. The examples below are illustrative; preserve source meaning before optimizing style.

A longer revision can be better when it clarifies agency, scope, or relationships. Do not alter passages that already work just to enforce consistency or introduce variety.

## Tool-assisted review

Resolve `SKILL_DIR` and `DOCUMENT` to absolute paths. Optional review:

```sh
uv run --offline "$SKILL_DIR/scripts/lint.py" --reading-load --json "$DOCUMENT"
```

Use cached dependencies. If they are unavailable, use manual review or obtain explicit installation permission rather than silently dropping `--offline`.

The reading-load lane points to long sentences, buried lists, kanji runs, double negatives, and 「の」 chains. It supplies locations for contextual review, not an instruction to change every hit. Its findings are separate from the ordinary findings/baseline comparison and must not become a score. Other concerns need direct reading even when lint is silent. Thresholds are implementation settings, not official writing rules.

The original imported catalog cited unavailable corpus reports and authorship-classification percentages. Those claims are not evidence for readability and are not used here. A pattern count cannot establish reader comprehension, a writing defect, or who authored the passage.

## A. Negation and condition scope

### A1. Double negatives

A double negative can make the reader work to recover the intended claim. It can also express a deliberate degree of uncertainty, reluctance, or qualified affirmation. Simplify only if that force survives.

- Before: 「負荷が増えないとは言えません。」
- Possible after: 「負荷が増える可能性は否定できません。」

The second is not necessarily shorter; it clarifies the remaining uncertainty. Neither means 「負荷が増えます」 or 「負荷が増えません」. Keep the source when no simpler equivalent fits. The reading-load tool can point to candidate negatives, but cannot determine their pragmatic force.

### A2. Nested conditions

Identify the premise, exception, and conclusion. A rewrite must preserve their logical relationships, not just reduce negation count.

- Before: 「設定が無効でない限り、再送が行われないということはない。」
- Possible after: 「設定が無効でなければ、再送は行われる。」

Invariant: the condition is **not disabled**. Do not automatically substitute 「有効なら」 when the system may have an unset or unknown state. Check the available states and context; do not infer a binary domain. There is no universal maximum depth of subordinate clauses.

## B. Dependency and reference distance

### B1. Several points crowded into one sentence

Split where an actor, point, or logical relationship changes. Repeat a condition if splitting otherwise detaches it from the governed claim.

- Before: 「資料が届いたら内容を確認し、問題がなければ承認しますが、不備があれば差し戻します。」
- After: 「資料が届いたら、内容を確認します。問題がなければ承認し、不備があれば差し戻します。」

Invariant: the same process and conditions. Inspect length as a cue, not a defect in itself. The public-writing commentary's 50–60-character cue is not a limit; actual tool thresholds are not writing requirements.

### B2. A mismatched subject and predicate

Check constructions such as 「理由は」「重視したのは」「目的は」 against their ending. Remove a redundant structure or split the thought without inventing the intended priority.

- Before: 「採用した理由は、費用を抑えられるため、この方式を選びました。」
- After: 「この方式を採用した理由は、費用を抑えられるからです。」

Invariant: the stated reason for adoption. When the original is too ambiguous to establish the intended reason, flag the ambiguity instead of guessing.

### B3. Competing modifiers

Move related words together or split a clause. Longer modifiers first can help, but use the intended attachment rather than a fixed sorting rule.

- Before: 「新しい、経理部が管理する申請システムを使う。」
- After: 「経理部が管理する新しい申請システムを使う。」

Invariant: the same new system and managing department. A different attachment can require confirmation.

### B4. Commas that change interpretation

Review comma placement for clause boundaries, attachment, and rhythm. Density alone is not useful evidence.

- Ambiguous: 「私は笑いながら走ってきた友人に手を振った。」
- Writer laughing: 「私は笑いながら、走ってきた友人に手を振った。」
- Friend laughing: 「私は、笑いながら走ってきた友人に手を振った。」

Do not choose between these readings without context. Reword if the intended reading remains hard to see.

### B5. Ambiguous attachment

A phrase such as 「所得が基準内の同居親族のいる高齢者」 can assign the income condition to different people. Identify the intended actor before clarifying.

- If the relative's income is constrained: 「所得が基準内の同居親族がいる高齢者」.
- If the older person's income is constrained: 「所得が基準内で、同居親族がいる高齢者」.

These are different eligibility conditions. A rewrite must not silently decide eligibility. A count of modifiers does not resolve the ambiguity.

### B6. Chained 「が」 clauses

「が」 can indicate contrast or simply connect clauses. When several uses obscure the real contrast, split and choose the correct connector.

- Before: 「再送できますが、すべてのエラーが対象ではなく、上限の設定も必要です。」
- After: 「再送できます。ただし、すべてのエラーが対象になるわけではありません。再送回数の上限も設定が必要です。」

Invariant: capability, limited error coverage, and the required limit setting. Do not change “not every error” to a specific unsupported exclusion list.

### B7. An unclear referent

Check what 「これ」「それ」「この」「その」 refers to. Replace with the exact supported referent when readers otherwise have to search backward.

- Before: 「設定ファイルとログを確認した。これを共有する。」
- If the source confirms the log: 「設定ファイルとログを確認した。ログを共有する。」

The conditional explanation matters: without context, the referent may be the file, log, or both. Do not infer it from preference.

## C. Word forms and terminology

### C1. Dense kanji compounds

A long compound can hide word boundaries or relationships. Expand it when it is descriptive text, not an exact name.

- Before: 「当該エラー起因再送抑制機能」
- After: 「このエラーが原因の再送を抑える機能」

Invariant: the same cause and function. Do not split official names, labels, or identifiers. There is no universal kanji percentage. The reading-load kanji-run cue is not a comprehension measurement.

### C2. Nominalization and 「の」 chains

A stack of nouns can hide the action and its actor. Consider a verb-based phrase if it preserves the relation.

- Before: 「運用コストの削減の実現を目指す。」
- After: 「運用コストの削減を目指す。」

Invariant: the same goal, not an achieved result. A more substantive verb-based alternative may be appropriate, but do not change 「寄与する」 into a guaranteed reduction. The number of 「の」 occurrences alone does not require an edit.

### C3. Passive voice and hidden agency

Passive voice can focus on the affected object, preserve unknown agency, or suit a formal record. Review it when responsibility matters and a known actor is obscured.

- Before: 「経理部によって承認された。」
- Possible after: 「経理部が承認した。」

Invariant: the same actor and completed approval. If the source only says 「承認された」, do not add 「経理部」. Preserve reported opinion in 「と考えられている」 rather than treating it as the author's own belief.

### C4. Unfamiliar loanwords

Choose words the audience understands or explain necessary terms. Keep exact product terminology and meaningful distinctions.

- 「アジェンダ」 → 「議題」 when it means the meeting topics.
- 「コンセンサス」 → 「合意」 when that is the intended meaning.

Do not use a near-synonym that changes a technical sense. Established words such as 「バス」 can be clearer than an artificial Japanese replacement. Consult `genre-notes.md` and the NINJAL source linked in `sources.md`.

## D. Economy of wording

### D1. Unnecessary wrappers

Remove a wrapper only when it adds no needed ability, courtesy, emphasis, or condition.

- Before: 「設定することができます。」
- Possible after: 「設定できます。」

Invariant: ability and polite register. 「設定します」 is not equivalent. Longer ability forms may help an accessible-Japanese audience. Do not widen a dictionary of matches into a universal ban.

## E. Paragraph and format choices

### E1. A wall of text or needless fragmentation

Use paragraph boundaries to expose topic or task transitions. A long paragraph may need subdivision; a sequence of one-sentence paragraphs may be a deliberate voice or a reference format.

Do not impose a paragraph-length target or merge every fragment. Grouping or splitting must preserve the relationships, order where meaningful, and source content. Format consistency can be useful; deliberate unevenness is not a quality goal.

## F. Parallel information

### F1. A list buried in prose

A list or table can help readers retrieve comparable items. The 2022 public-writing guidance suggests considering bullets for three or more parallel pieces of information; this is not a requirement to make everything a three-item list.

- Before: 「本機能は、再送、再送回数の上限管理、再送間隔の調整を行います。」
- After:

  > 本機能は次の処理を行います。
  > - 再送
  > - 再送回数の上限管理
  > - 再送間隔の調整

Invariant: exactly those functions, with no new ranking or sequence. Number only if order matters. The reading-load buried-list cue may mistake a parenthetical list or miss a verb-based list; direct review decides.

## G. Familiar phrases

Use `forbidden-patterns.md` to review summaries, emphasis, transitions, caution, and dramatic phrasing. Use `translationese.md` for construction alternatives. Neither is a ban list, and a match is not evidence of authorship.

## H. Paragraph-level relationships

### H1. Restatement with or without new information

A second phrasing may be padding, a useful explanation for beginners, or a distinct consequence. Delete only when its function is genuinely redundant.

- Before: 「このAPIは冪等です。同じリクエストを何度送っても結果は変わりません。」
- Possible after: 「このAPIは冪等で、同じリクエストを何度送っても結果は変わりません。」

Invariant: both the term and its explanation. Do not delete 「再送しても安全です」 as a mere synonym: it is a separate safety claim, and idempotence alone need not justify it. Keep or flag that claim according to the editing scope and evidence.

### H2. An abrupt topic shift

Provide an accurate bridge or separate topics when readers cannot see how they relate. Do not invent causation to create a smoother transition. Preserve narrative discovery when it is intentional.

Outline extraction can help inspect topic order; only reading the content establishes whether the links are adequate.

### H3. Connectors with the wrong scope

Check addition, contrast, sequence, reason, and consequence. Remove redundant connectors only when the relationship remains clear.

- Before: 「ログを出力します。一方、メトリクスも送信します。」
- Possible after: 「ログを出力します。また、メトリクスも送信します。」

Use the alternative only if the original intends addition rather than contrast. Do not vary synonyms just to change sentence openings.

## I. Notation and exact wording

### I1. Inconsistent spellings

Check 「ユーザー／ユーザ」「サーバー／サーバ」「行う／行なう」 against the document's conventions. Standardize when readers might mistake one concept for two. Preserve quotations, source titles, UI labels, and genuinely different terms. A single variant is not automatically a defect.

### I2. Mixed punctuation styles

Choose appropriate conventions for prose, citations, mathematics, and code. Mixed 「、。」 and 「，．」 may deserve review, but quoted source conventions and technical notation can legitimately differ. Do not alter literal output.

### I3. Mixed numeral styles

Consistent numeral presentation can aid comparison in tables and lists. Do not change the numerical value, unit, significant precision, date interpretation, or exact identifier while normalizing full-width and half-width forms. Different contexts can justify different notation.

### I4. Line breaks that obscure a phrase

Check whether rendered line breaks split a semantic unit or damage readability. Respect the requested medium and its line-breaking conventions. Markdown layout changes alone are outside this skill's language-editing scope unless they affect comprehension or are part of the requested document edit.

### I5. Similar-looking or same-sounding words

Check 「意志／意思」「保証／保障／補償」 and similar distinctions against meaning and specialized usage. Do not silently normalize a legal term or quote. An uncertain substitution needs source confirmation.

## J. Whole-document purpose

### J1. The needed answer arrives too late

For a decision memo, report, or task guide, place the supported main answer early enough to orient readers. A chronological record or essay may use another order. A section-specific answer can appear in its relevant later section; it need not be duplicated at the beginning.

Do not write a stronger opening than the evidence supports or replace an unresolved question with a conclusion.

### J2. A term exceeds the audience's assumed knowledge

Define or explain unfamiliar terms at the first useful occurrence. A glossary can support lookup; an inline explanation can support reading. Experts may not need either. Preserve exact names and technical senses.

Optional `terms.py` output is a partial prose inventory: it excludes lists, block quotes, tables, code, and frontmatter. Review those regions directly, especially in minutes and slides. Explanation markers do not prove understanding, and their absence does not prove a missing definition.

### J3. A second storyline distracts from the explanation

In a task-oriented explanation, repeated suspense, foreshadowing, and dramatic reveals may delay the answer. Retain discovery order when it supplies evidence or is central to an essay. Remove only decorative staging that can disappear without losing facts, causality, attribution, or the author's stance.

There is no quota of dramatic phrases or “one reveal only” rule. Judge the actual document's purpose.

## Final preservation check

After changes:

- Compare the source and revision for facts, actors, status, modality, negation, condition scope, and causal force.
- Confirm that deleted passages carried no distinct evidence, exception, implication, or reader support.
- Restore distinctions lost by simplifying a phrase or moving it into a heading.
- Preserve appropriate voice, useful templates, exact quotes, and technical identifiers.
- Accept increased length when it improves understanding without adding unsupported content.
- Stop when substantive issues are addressed; do not chase pattern counts or an arbitrary score.
