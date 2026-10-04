# Revision workflow and decision record

This reference supplies editorial heuristics for the workflow in `SKILL.md`. Its goal is to improve the document for its reader while preserving the source, not to remove all recognizable patterns or achieve a detector score. See [sources.md](sources.md) for primary guidance and limits.

## Before drafting: reader, purpose, and level of detail

Identify what readers need to understand or do. Choose the relevant document type and note the supported main message. A document can have no settled conclusion: make the unresolved question visible instead of manufacturing a position.

Allocate detail according to complexity, evidence, reader knowledge, and importance. Do not make every section equally long by default, but do not introduce unevenness, emotional intensity, or a ranking merely to seem less formulaic. Parallel comparisons and stable procedures often benefit from consistent structure.

For a rewrite, keep sections and passages that already serve their purpose. Change only where the reader benefit is explainable. There is no percentage limit on edits and no quota of headings to rewrite; a severe structural problem may need a large revision.

## Gathering material for new writing

Separate supplied facts, researched facts, hypotheses, and proposed wording. Search for evidence relevant to the actual claim, favoring primary sources. Check dates, populations, conditions, units, and whether a source supports the full statement rather than just adjacent terminology.

Use this sequence as needed:

1. State the question or tentative claim and identify the evidence it would require.
2. Consult available source material or research that evidence.
3. Adjust the claim to the findings, not the findings to the desired claim.
4. Stop when the requested scope is adequately supported; do not accumulate irrelevant detail.

A lack of names, numbers, or anecdotes is not automatically a material gap. Definitions and general guidance can be useful without them. Never invent statistics, personal experience, quotations, customer reactions, or motives. If essential information is unavailable, ask a targeted question or state the precise missing prerequisite. Finish the parts that the material does support.

## Fidelity review: before stylistic changes

Check the source and draft side by side for:

- Facts, numbers, dates, units, names, and exclusions.
- Speaker attribution and agency: who said, proposed, agreed, or must act.
- Modality: possibility, permission, obligation, intention, forecast, and decision.
- Negation, condition scope, uncertainty, and quantifiers such as 「一部」「多く」.
- Causal versus merely chronological relations.
- Status: suggested, discussed, agreed, deferred, or unknown.
- Genre, relationship, and the author's supported stance.

Do not improve a heading by strengthening the body. Do not add a deadline or owner to make an incomplete action record look complete. See `doctypes/minutes.md` and `examples.md` for counterexamples.

## Using optional tools

Resolve `SKILL_DIR` to the absolute skill directory and `DOCUMENT` to the absolute target path. The examples do not assume a particular working directory.

```sh
uv run --offline "$SKILL_DIR/scripts/lint.py" --json "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/lint.py" --genre business --reading-load --json "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/outline.py" "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/terms.py" "$DOCUMENT"
```
Use cached dependencies with `--offline`. If packages are unavailable, use manual review or obtain explicit installation permission; do not silently drop the offline flag.


Choose `essay`, `tech`, or `business` only when the genre is appropriate; profiles are tool settings, not validated guarantees of lower false positives. The outline helps inspect navigation, and the term inventory helps locate definitions. Neither proves that the document's structure or terminology is adequate.
The term inventory excludes lists, block quotes, tables, code, and frontmatter. Inspect excluded regions directly; minutes and slides can place most important terminology there. A definition marker is only a cue, not evidence that the reader understands the term.


Tool findings are review candidates. Severity is the tool's label, not proof of a defect, authorship, or reader comprehension. Counts, zero findings, and lexical density are not quality scores. If a tool cannot run, use `manual-checklist.md` and disclose the limitation when relevant.

### Responding to finding categories

The names below identify tool outputs, not mandatory editing rules. Some are experimental and depend on flags or the tool version.

| Finding category | Contextual review question | Safe action or reason to retain |
|---|---|---|
| `forbidden_phrase` | Does the matched wording obscure the point, add empty emphasis, or express a needed stance? | Consult `forbidden-patterns.md`. Keep quotations, names, necessary hedges, and useful transitions. |
| `translationese`, `translationese_morph` | Can the wording be made more direct without changing ability, permission, cause, condition, or register? | Consult `translationese.md`; do not blindly apply a replacement table. |
| `antithesis_repetition` | Do the contrasts each carry a distinct exclusion or correction? | Simplify redundant contrasts; preserve their logical exclusions. |
| `low_sentence_variance`, `low_burstiness` | Is the prose hard to follow, or are comparable items simply similar in length? | Revise unclear sentences, not the statistical distribution. Never add long sentences or fragments to change a metric. |
| `nominal_ending` | Are fragments appropriate to this genre and understandable? | Minutes, headings, and slides may need noun endings. Do not add or remove them to satisfy a rate. |
| `paragraph_lead_conjunction` | Does each connector express the actual relationship? | Preserve necessary condition, contrast, and causal markers; remove only empty ones. |
| `uniform_paragraph_structure` | Does the structure help comparison or unnecessarily pad each point? | Keep helpful templates; trim unsupported padding. |
| `repeated_sentence_lead`, `repeated_syntax_template` | Is repetition useful emphasis or a confusing restatement? | Keep deliberate parallels; revise only when meaning becomes clearer. |
| `low_lexical_diversity_ttr`, `low_lexical_diversity_mtld` | Does a vague word hide missing detail? Is repeated terminology precise? | Supply verified detail if needed. Do not rotate technical synonyms. |
| `english_syntax_inanimate_subject`, `inanimate_subject_morph` | Is the subject–predicate relation idiomatic and accurate? | 「データが示す」 may be entirely appropriate. Do not invent a person or turn implication into proof. |
| `english_syntax_cleft_because` | Would the reason be clearer in another arrangement? | Keep a two-sentence explanation when it helps; preserve the same reason. |
| `high_bold_density`, `high_bullet_ratio`, `boilerplate_heading`, `numbered_phase_structure`, `high_emoji_symbol_density` | Does the formatting support navigation, comparison, safety, or established conventions? | Change only for reader benefit; lists, numbering, labels, and symbols are not forbidden. |
| `low_specificity` | Does this passage need concrete evidence for its actual claim? | General principles can remain general. Do not inject arbitrary names or numbers. |
| `semantic_topic_flatness` | Are nearby sentences unnecessarily restating a point, or coherently developing it? | Review the content; do not add tangents or change viewpoint merely to vary similarity. |

The optional `--reading-load` lane points to long sentences, buried lists, kanji runs, double negatives, and 「の」 chains. Treat its findings as prompts to inspect the passage, not instructions to shorten or simplify indiscriminately. Do not merge these counts into a score. The nested-modifier review remains useful even without a dedicated detector.

The separate experimental command below may require dependency installation and a model download. Obtain explicit permission for those actions; choosing full review does not authorize them. Uv's offline flag governs packages, not model-library networking. Use model offline mode or a reviewed local path for cached-only operation. Review model provenance and document privacy, and obtain separate consent before enabling `--trust-remote-code`, which executes model-repository Python. Do not add that flag or switch models automatically after a load failure. See `diagnose.md` for the complete experimental safety boundary.

```sh
uv run --offline "$SKILL_DIR/scripts/semantic.py" --json "$DOCUMENT"
```

Custom `--model` output is metrics-only, with `flatness_threshold: null` and no threshold-based flatness finding. Do not apply a default-model threshold to a different embedding space.

## Structure review

Read headings and paragraph openings together. Ask:

- Can the intended reader locate the main answer or requested decision?
- Does the order reflect the task, procedure, chronology, or argument?
- Do headings identify the content without overstating certainty?
- Are comparisons parallel and causal claims supported?
- Is detail allocated usefully, without mandatory variation?
- Does the ending fulfill the document's purpose without adding unsupported recommendations?

For explanations and reports, the writer's discovery order need not be the reader's order. Present results early when that helps, but preserve chronology where it is evidence. Narrative writing can legitimately reveal a conclusion later. Do not reduce every case study to the same opening summary.

## Sentence clarity review

Use `readability-principles.md` and `readability-antipatterns.md` where needed. Prioritize meaning-sensitive problems—negation, conditions, attribution, modifier attachment—before cosmetic changes. Review paragraph connections, sentence relations, terminology, and tone. Do not apply every catalog entry on every pass.

After splitting a sentence, restore the scope of its conditions and qualifiers in each affected clause. After deleting a restatement, confirm it did not contain a distinct exception, implication, example, or audience aid.

## Decision record

For a consequential edit, record the issue, the decision, and the reason. Keep the record in the conversation or an owned temporary location; do not create repository files unless requested. Group repeated low-impact findings when the same reasoning applies.

```text
- [changed] Clarity: split the sentence while preserving the stated condition and actor.
- [kept / exact name] 「多角的レビュー機能」 is the supplied product name.
- [kept / scope] 「～ではなく」 excludes an alternative that the reader must distinguish.
- [kept / audience] 「～することができます」 makes ability explicit for this audience.
- [needs information] The source does not identify an action owner; no owner was invented.
```

A finding that remains after review is not an unresolved defect if there is a sound reason to retain the wording. Do not repeatedly reconsider a retained finding unless the context changes.

### Optional baseline comparison

If a previous lint JSON file already exists in an owned temporary location, it can help navigate changed findings:

```sh
uv run --offline "$SKILL_DIR/scripts/lint.py" --json --baseline "$PREVIOUS_JSON" "$DOCUMENT"
```

Here `PREVIOUS_JSON` is the absolute path to that output. The tool's resolved/new/persisting labels describe matches, not semantic regression or improvement. Inspect relevant changed passages even when a match disappears.

## Avoiding unproductive revision

If an edit repeatedly loses meaning, cycles between equivalent styles, or creates new confusion, return to the source and reader's task. Keep the original with a reason, choose a clearer structure, or resolve missing information. Do not introduce word substitutions simply to evade a pattern match.

Never sweep the entire document with a stylistic transformation. Preserve useful task labels, parallel bullets, quotations, idiomatic phrasing, stable terminology, and authorial voice. An existing open question must stay open unless new evidence or an explicit author decision resolves it.

## Final pass and stopping conditions

Apply `eval-rubric.md` qualitatively. Stop when:

1. The requested content is present and source meaning is preserved.
2. Substantive reader-facing issues found in review are addressed or retained with an explanation.
3. Changed passages work in context without a new meaningful regression.
4. Missing information and verification limits are honestly disclosed.

Do not require zero tool findings, synthetic sentence variation, personal warmth, or a minimum numeric score. A final read-through checks what the tools cannot; it is not an invitation to keep polishing indefinitely.

## Temporary files

Prefer not to create intermediate files. If necessary, use a clearly owned temporary directory, not the user's document directory. Remove only the intermediates created for this task when finished. Do not delete user inputs, existing backups, source evidence, or useful artifacts the user asked to retain. The final deliverable is the requested document and, only when requested, a style profile.
