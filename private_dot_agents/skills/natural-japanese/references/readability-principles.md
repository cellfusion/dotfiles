# Sentence clarity principles

Use these principles to reduce avoidable rereading while preserving meaning. **Source guidance** comes mainly from the 2022 public-writing recommendation, especially III-3 and III-4; [sources.md](sources.md) links the final document and explains its scope. The review questions and illustrative examples below are **editorial heuristics**, not measured rankings of cognitive difficulty.

## Modifier order and attachment

Put related words close enough that readers can tell what modifies what. When several clauses compete for the same predicate, a longer clause first may be easier to follow; moving a clause into its own sentence may be better. Do not turn this into a rigid ordering algorithm.

- Before: 「会議で提案された新しい、経理部が管理する申請システムを使う。」
- After: 「会議で提案された、経理部が管理する新しい申請システムを使う。」

Invariant: the same system, proposal, and managing department. When attachment is genuinely ambiguous, identify the possible readings and ask or retain the ambiguity; do not silently choose an interpretation.

## Punctuation that clarifies meaning

Place commas where they help readers recognize boundaries or attachments. Avoid splitting a tight phrase without a reason. Rhythm and medium also matter; commas are not governed solely by breathing or by a fixed density.

- Ambiguous: 「私は笑いながら走ってきた友人に手を振った。」
- If the writer was laughing: 「私は笑いながら、走ってきた友人に手を振った。」
- If the friend was laughing: 「私は、笑いながら走ってきた友人に手を振った。」

The alternatives encode different meanings. Select only from supported context; punctuation is not a fact-free cosmetic edit. Reword if commas alone do not resolve the intended meaning.

## Sentence focus and length

A sentence is easier to follow when its main point and clause relationships are clear. Split when several independent points, conditions, or shifts of actor are hard to track. Preserve the relationships with accurate connectors or repeated conditions.

The 2022 public-writing commentary suggests inspecting readability once a sentence reaches about 50–60 characters and explicitly says there is no universally appropriate length. This is neither a maximum nor a target. Do not lengthen short sentences or insert fragments to create statistical variation.

- Before: 「資料が届いたら内容を確認し、問題がなければ承認しますが、不備があれば差し戻します。」
- After: 「資料が届いたら、内容を確認します。問題がなければ承認し、不備があれば差し戻します。」

Invariant: review follows receipt; approval and return retain their respective conditions. More characters can be justified when they clarify scope. Among equally accurate, useful candidates, prefer the one that is easier to read—not necessarily the shortest.

## Subject–predicate alignment and agency

Check that the sentence beginning and ending fit. If a sentence starts with 「理由は」, its predicate should state a reason rather than unexpectedly become an action. A long interruption can hide a mismatch.

- Before: 「採用した理由は、費用を抑えられるため、この方式を選びました。」
- After: 「この方式を採用した理由は、費用を抑えられるからです。」

Keep explicit actors where readers need them. Japanese can omit a subject when context makes it clear. Do not introduce a named actor when the source does not identify one.

## Paragraph focus

Group information around a useful topic. In an explanation or report, a topic sentence near the start can help readers place the supporting details. A chronological record or essay can use another arrangement.

Do not convert a sequence into causation. 「負荷が上がった。設定に不備が見つかった。」 does not alone establish that the setting caused the load. A paragraph-opening summary must remain within what the body actually proves.

## Connectors and logical scope

Use a connector when readers need help recognizing a relation: addition, contrast, reason, consequence, alternative, or condition. Its scope must match the intended relationship.

- Before: 「今回はUIを更新した。一方、バグも1件修正した。」
- After: 「今回はUIを更新した。また、バグも1件修正した。」

This alternative is appropriate only when the two changes are additions rather than an intended contrast. Do not substitute 「そのため」 merely because the second event occurred later. Do not rotate 「しかし」「一方」「ところが」 for variety; they can differ in meaning and scope.

## Endings, register, and useful repetition

Preserve the appropriate relationship and genre: 「です・ます」, plain style, record fragments, quoted speech, and UI wording serve different purposes. Repeated polite endings are not inherently unnatural. A consistent procedure or comparison can be easier to read than stylistic variation.

Where repetition truly obscures the message, combine or split clauses without changing tone or modality. Do not change polite prose to plain prose, or introduce an assertion or question, just to break a run of similar endings.

## Facts, interpretations, and uncertainty

Make evidence and inference distinguishable. Retain estimates and qualifiers in the clause they govern. Attribute opinions to their actual speaker; do not create an author's opinion to fix an unsupported assertion.

- Before: 「利用者数は伸び悩んでいる。UIが原因かもしれない。」
- After: 「利用者数は伸び悩んでいる。原因はUIにある可能性がある。」

Invariant: the UI remains a possibility, not a demonstrated or likely cause. Do not add 「先週比3%増」 or upgrade to 「可能性が高い」 without evidence.

## Reader knowledge and purpose

Ask what the reader knows, what they need, and how they will use the text. Define unfamiliar terms when needed, but keep exact terms in an expert specification or searchable reference. The same term may need a plain explanation in public communication and no explanation in a specialist table.

The primary accessible-Japanese guideline recommends audience adjustment and comprehension checks rather than strict universal criteria. It also shows that 「することができます」 can be useful for ability. See `genre-notes.md` before treating concise language as the only suitable language.

## Meaning-sensitive simplification

Pay particular attention to negation, quantifiers, and modality:

- 「増えないとは言えない」 is not equivalent to 「増える」.
- 「すべてが失敗したわけではない」 is not equivalent to 「すべて成功した」.
- 「利用できる」 does not always mean 「利用してよい」.
- 「検討する予定」 is not a commitment to implementation.

If a simpler paraphrase cannot preserve these distinctions, keep the original or flag the ambiguity. The companion `readability-antipatterns.md` supplies localized repair examples; `examples.md` supplies fidelity counterexamples.
