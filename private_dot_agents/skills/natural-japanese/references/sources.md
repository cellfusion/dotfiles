# Sources and limits of the guidance

This skill adapts Japanese writing guidance to editing tasks. **Source guidance** below summarizes the linked primary documents. **Editorial heuristics** elsewhere in this directory are practical review questions, not official standards or experimentally established laws. None of these sources validates AI-authorship detection or a numerical naturalness score.

## Public writing: Council for Cultural Affairs, 2022

- [Official publication page: 公用文作成の考え方（建議）](https://www.bunka.go.jp/seisaku/kokugo_nihongo/kokugo_shisaku/94336802.html)
- [Final recommendation and commentary, dated 7 January 2022](https://www.bunka.go.jp/seisaku/bunkashingikai/kokugo/hokoku/pdf/93651301_01.pdf)

Page references below use the document's printed pagination: the recommendation has parenthesized page numbers; the commentary starts again at page 1. Use the section names when a PDF viewer's page count differs.

| Source location | Source guidance | Adaptation and boundary |
|---|---|---|
| Basic approach 1; recommendation pp. (1)–(2), commentary pp. 2–4 | Write for the reader and the document's purpose; distinguish notices, records, and public explanations. | Do not impose one style or structure on every genre. These are public-writing recommendations, not mandatory rules for essays or all business documents. |
| Basic approach 2(1)–(2); commentary pp. 5–6 | Preserve the original information's content and meaning; balance accuracy and clarity. | Fidelity overrides brevity, rhetorical polish, and detector findings. Do not invent an actor, number, conclusion, or deadline. |
| II-2–4; commentary pp. 22–24 | Replace unfamiliar terminology, explain it, or retain it when readers should learn the term. Established loanwords can remain. | Choose explanations for the actual audience. Definition-first and function-first are alternatives, not competing universal rules. |
| II-5; commentary pp. 25–26 | Avoid confusing wording and needless repetition. Example: 「利用することができる」 → 「利用できる」. | Shorten only when ability, permission, conditions, emphasis, and register survive. |
| II-7; commentary p. 28 | Consider readers' feelings; avoid excessive restrictions or prohibitions on particular words. | A lexical match is a review candidate, not a universal ban. |
| III-2; commentary p. 31 | Make titles and headings identify the topic and document type; use headings that help readers grasp the whole. | Task labels such as 「申請方法」 can be effective. Headings must not strengthen the body’s certainty. |
| III-3; commentary pp. 32–33 | Keep sentence points clear; clarify subject–predicate relations and modifier attachment; consider lists for three or more parallel pieces of information. | Match the form to the content. Keep ordered procedures ordered; do not invent causal links between list items. |
| III-3(a); commentary p. 32 | At about 50–60 characters, consider whether a sentence has become difficult to read; an appropriate length cannot be fixed universally. | This is a review cue, not a maximum length or a target sentence-length distribution. |
| III-3(i)–(j); commentary p. 33 | Avoid unnecessary passive constructions and double negatives, while allowing effective uses. | Preserve unknown agency, emphasis, uncertainty, exceptions, and logical scope. |
| III-4; commentary p. 34 | Show conclusions early, then reasons and details; adapt structure to purpose. Recurring documents may benefit from consistent formats. | Do not disrupt a stable reference template merely to introduce variation. Narrative discovery and procedural order can justify other arrangements. |

## Accessible Japanese: Immigration Services Agency and Agency for Cultural Affairs, 2020

- [Official publication page: 在留支援のためのやさしい日本語ガイドライン](https://www.moj.go.jp/isa/support/portal/plainjapanese_guideline.html)
- [Final guideline, August 2020](https://www.moj.go.jp/isa/content/930006072.pdf)

Source guidance: Chapter 2, printed pp. 5–10, proposes three stages: organize the information, adapt words and notation for the intended non-native readers, and have Japanese-language teachers or intended readers check comprehension. Page 5 explicitly declines strict criteria because language backgrounds and abilities vary.

Important qualifications:

- Prefer familiar words and clarify necessary technical terms. This is not a general ban on katakana or a requirement to restrict every document to a JLPT vocabulary level.
- The guideline favors short sentences, but does not prescribe a universal 24-character maximum.
- Page 9 favors direct expressions but explicitly permits 「～かもしれません」 and 「たぶん～です」 when an assertion would be problematic. Simplicity must not turn uncertainty into certainty.
- Page 10 gives 「することができます」 as an ability expression. An expression that is wordy in one context may help another audience.
- Furigana, explicit dates, illustrations, and accessible layout may help; choose them for the reader and medium. Simplified Japanese does not replace necessary multilingual support.
- Some source examples simplify or add context for an administrative communication task. They are not permission to add unverified facts during a faithful rewrite. Confirm any missing practical information before adding it.

## Terminology: National Institute for Japanese Language and Linguistics

- [「外来語」言い換え提案](https://www2.ninjal.ac.jp/gairaigo/)

This primary institutional resource supplies alternatives and explanations for loanwords in public communication. It is historical: the site states that its content is current through September 2009 and will not be updated. Consult the entry for the intended sense and assess current usage; a suggested replacement need not preserve every specialized meaning. See `genre-notes.md` for audience-specific use.

## Practitioner perspective: Hiroshi Yuki

- [文章を書く心がけ](https://www.hyuki.com/writing/writing.html)

This is the author's own writing advice, not an official standard or a controlled study. Useful review ideas include imagining the reader's prior knowledge, introducing unfamiliar ideas gradually, rereading aloud, and checking examples against original sources. The page also notes that there is no universal method. Its contextual suggestions should not be converted into mandatory quotas or score thresholds.

## What this skill does not claim

Sentence-length variance, repeated expressions, nominal endings, lexical diversity, and embedding similarity describe aspects of a text. They do not establish its author, a probability of AI generation, comprehension for a particular reader, or a scientifically calibrated quality score. Imported references to unavailable corpus reports and unsupported detection percentages are not evidence and are not retained as authority here.

The genre templates, review ledger, qualitative rubric, and before/after examples are this skill's editorial heuristics. Japanese examples are illustrative unless a source is named; fictional samples are explicitly labeled. Evaluate an edit by what it helps a reader understand **and** what it preserves.

## Repository developer verification

From this repository checkout, the focused regression command is:

```sh
bash tests/test-natural-japanese.sh
```

It needs `uv` and cached Sudachi-related packages, uses `--offline`, and does not load an embedding model. The checks cover implemented tool behavior; they do not establish that edited prose is broadly superior or measure human comprehension. Do not claim a test result unless that run was actually observed.
