# Diagnosis without rewriting

Use diagnosis when the user asks for critique, a score, or whether a passage sounds formulaic. Do not change the document unless a rewrite is requested. Identify reader-facing issues, cite representative passages, and explain what would help.

**Style cannot establish authorship.** Do not infer that AI wrote a passage, assign an AI-generation probability, or describe a detector finding as evidence of authorship. If asked 「この文章AIが書いた？」, explain that wording alone cannot determine this, then offer grounded stylistic observations.

## Review depth

These labels retain the invocation vocabulary in `SKILL.md`; they describe review depth, not detector confidence. Let `SKILL_DIR` be the resolved absolute skill directory and `DOCUMENT` the resolved absolute input path. Do not assume the user's working directory is the skill root.

- **quick**: Read the document and identify the highest-impact issues. Inspect its headings and opening sentences. A single optional lint run can supply candidates; tool availability does not determine whether the critique is valid.
- **full**: Add fidelity, structure, sentence clarity, terminology, and genre review. Optional outline and term tools assist navigation; the reviewer still decides what needs explanation. Diagnose once rather than running an editing loop on an unchanged document.
- **exp**: Add the experimental embedding-based tool only after explicit permission for any dependency installation or model download. It uses torch and sentence-transformers and may download a model of approximately 1 GB on first use. If permission is absent, finish the reachable full review and state that the experimental tool was not run.

```sh
uv run --offline "$SKILL_DIR/scripts/lint.py" --json "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/outline.py" "$DOCUMENT"
uv run --offline "$SKILL_DIR/scripts/terms.py" "$DOCUMENT"
```

Where appropriate, lint accepts `--genre essay|tech|business` and the optional `--reading-load` review lane. The experimental command is:

```sh
uv run --offline "$SKILL_DIR/scripts/semantic.py" --json "$DOCUMENT"
```

`--offline` prevents uv from fetching uncached packages. If required packages are unavailable, use manual review or obtain explicit installation permission; do not silently retry without `--offline`. Uv's flag does not itself make model loading offline. For a cached embedding model, use the model library's offline mode (for example, `HF_HUB_OFFLINE=1`) or a reviewed local model path, and do not claim that uv alone prevents model downloads.

Before experimental use, check model provenance, expected disk/network costs, and whether handling the document in this environment is authorized. `--model` selects the model; prefer a trusted reviewed model or local path. Loading normally does not submit document text as a remote inference request, but dependencies and model code can create privacy risk. Do not send private content to an external service or execute unreviewed model code under an assumption of local safety.

If the selected model requires repository Python, `--trust-remote-code` explicitly permits that code to execute. Its default is false. Obtain separate explicit consent for remote-code execution, independently of package-installation or model-download permission. A model-load failure does not authorize a retry with that flag, a substitute model, or a hidden fallback. Report the actionable limitation and complete the reachable manual/full review.

Embedding similarity can highlight similar adjacent sentences. A coherent explanation, procedure, or repeated legal formula may require exactly that similarity. It does not reveal a hidden layer of AI authorship, and it is not a quality metric.
With a custom `--model`, treat the output as metrics only: the threshold is reported as `flatness_threshold: null`, and no threshold-based flatness finding is produced. Do not reuse the default model's threshold for another embedding space. Neither default nor custom metrics are validated measures of prose quality.

`terms.py` is a partial prose inventory: it excludes lists, block quotes, tables, code, and frontmatter. Review those regions directly, especially in minutes and slides. Marker presence does not prove that a definition is correct or useful.


## Scores: only when requested

Prefer a qualitative critique unless the user explicitly requests a score, including invoking `score`. Use the six editorial dimensions in `eval-rubric.md`, not counts or severity weights from lint.

A requested 0–100 score is a **subjective editorial estimate for the stated reader, purpose, and genre**. Higher means the passage better meets those editing criteria. It is not a probability, measured naturalness, a calibrated detector output, or proof that a human wrote it. Do not use score bands such as “AI-like” or “human-like,” impose a pass threshold, or revise until an arbitrary target is reached.

For a numerical result:

1. State the assumed audience and purpose.
2. Name the applicable rubric dimensions and explain their assessment with cited passages. Mark dimensions unsupported by the material as not assessable.
3. If one overall number is requested, use the equal-weight mean of the assessed dimensions, rounded to a whole number. Disclose the components and omitted dimensions. This averaging is a reporting convention, not a validated measurement.
4. State the limitation explicitly: 「この点数は、想定読者に対する読みやすさの編集上の目安です。AIが書いた確率や作者の判定ではありません。」

Do not score an empty input. A short email or sentence may still be reviewed: limit the assessment to what the sample supports instead of inventing a minimum character count or claiming that every dimension can be measured.

## Output

Keep the response proportional to the document:

- An overall assessment, with an editorial score only if requested.
- A few high-impact observations, quoting the passage or giving reliable line numbers. Explain the reading difficulty, missing evidence, or genre mismatch—not merely the tool category.
- Changes worth considering, in order of likely reader benefit. Mention deliberate wording that should remain when useful.
- Any review limits: missing source material, assumed audience, or tools not run. Do not claim that diagnosis verified external facts unless it did.

A diagnosis can include a clearly labeled illustrative alternative without silently replacing the document. Do not turn an unresolved source claim into an asserted conclusion in that example.

### Example response to an authorship question

> 文体だけでは、AIが書いたかどうかは判断できません。「重要なのは」が各段落の冒頭で繰り返され、何を優先すべきかが読み取りにくくなっています。一方、製品名と操作手順は具体的なので、そのまま残すのがよさそうです。

This response names an observable pattern and its effect without making an authorship inference.

## Evidence boundary

See [sources.md](sources.md). The primary writing sources support audience-aware clarity and fidelity; they do not validate the scoring convention above. Treat lint severity as a tool's prioritization hint, not the magnitude or certainty of an editorial problem.
