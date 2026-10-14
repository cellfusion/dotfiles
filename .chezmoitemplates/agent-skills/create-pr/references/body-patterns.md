# Choose the explanation, not a universal template

Use this matrix as selection guidance. Combine lenses for mixed changes. Do not emit unused headings
or an exhaustive checklist. Follow repository-required headings and truthfully fill their checkboxes.

| Change | Explain for the reviewer | Useful evidence / format |
| --- | --- | --- |
| Feature | User problem, before/after, supported flow, important constraints, why this approach | Concrete usage, acceptance criteria, source/design links |
| Bug fix | Trigger, expected versus actual behavior, root cause, why the fix addresses it, regression scope | Minimal reproduction and failing-before/passing-after evidence when available |
| API / specification | Spec-only or implemented, operation intent, inputs/outputs, errors, auth, client impact | Endpoint inventory and per-operation examples; API reference |
| UI / accessibility | User-visible states, interactions, error/loading/empty states, keyboard/accessibility impact | Sanitized before/after screenshots when available; actual surface observation |
| Refactor | Why the boundary/dependency changes, what behavior must stay invariant, affected callers | Before/after dependency description, consumer-facing checks; no unsupported “動作変更なし” |
| Performance | Bottleneck, mechanism changed, workload/environment, measured result and limits | Comparable before/after measurements with units/sample conditions; no invented improvement |
| DB / data migration | Schema/data changes, affected readers/writers, execution order, backfill/locking risks | Compatibility window, migration checks, rollback feasibility including irreversible data loss |
| Config / infrastructure / CI | Previous/new setting, environment/platform scope, permissions/secrets, rollout effect | Render/config check and relevant command output; distinguish defined from applied/deployed |
| Dependencies / security | Versions/reason, affected behavior, compatibility/advisory, permission/trust boundary | Lockfile/runtime check, specific advisory where applicable; no blanket security assurance |
| Docs / tests only | Incorrect/missing guidance or behavior covered, corrected expectation, remaining scope | Relevant example/link/render check; do not claim product behavior changed |

## Core shape

This is a starting point, not headings to copy blindly:

```markdown
## 概要
どの問題に対して、利用者や開発者から見て何が変わるか。

## 変更内容・理由
- 重要な変更と、その判断を支える理由。

## 確認
- 実行したコマンド／シナリオと結果。
- 未確認の範囲と理由（該当する場合）。
```

Expand only where the reviewer needs it:

- **背景・設計判断:** constraints and alternatives actually considered; attribute the decision.
- **影響・互換性:** consumers, default behavior, existing data and public contracts. Unknown is not none.
- **導入・切り戻し:** order, prerequisites, feature flags, rollback limitations, only if relevant.
- **レビューしてほしい点:** concrete decision or risk, important file/symbol and reading order.
- **関連:** issues, design docs, dependent PRs. Use neutral `Related: #123` by default. Use closing
  keywords only for intended complete resolution and make that merge side effect visible in preview.
  GitHub interprets body closing keywords only when the PR targets the default branch.

For a small docs change, summary, a reasoned change bullet and a truthful check can be enough.
For a bug, prioritize trigger → cause → changed behavior → regression evidence over architecture.
For a specification-only change, say “仕様を定義するPR。サーバー実装・デプロイは含まない” when the
fixed diff supports that statement; do not say the endpoint is already usable.

## Bug fixes: explain the causal chain

Choose this lens from changed behavior and evidence, not a `fix:` prefix alone.
Record the trigger and expected/actual result, the confirmed cause, and how the changed mechanism
prevents recurrence. Call out adjacent behavior intentionally unchanged and remaining affected
conditions. If the root cause is not established, say so; do not describe a hypothesis as diagnosed.
Separate pre-fix reproduction, post-fix verification and test coverage. Tests added in the diff
are not proof they ran. Do not force an API section into a CLI, UI, scheduler or filesystem bug.

Illustrative shape; replace all fictional facts with branch evidence:

```markdown
## 概要
絞り込み後に次ページへ進むと条件が外れる不具合を修正する。

## 発生条件・原因
検索語を入力してから次ページへ進むと、全件表示に戻っていた。
ページ切り替え時に検索語を引き継がず、ページ番号だけを更新していたことが原因。

## 修正内容
ページ切り替え後も検索語を保持する。検索語を変更した場合は従来どおり先頭ページへ戻る。

## 確認
変更したコードと回帰テストを確認。テスト・画面操作は未実行のため、
絞り込み後のページ移動と検索語変更時の動作を確認する必要がある。
```

If actual failing-before/passing-after evidence exists, replace the not-run wording with the
specific command/scenario and observed results. Never claim a regression test was added unless it was.

## New features: explain the user flow and boundaries

State the problem/use case, who can do what after the change, and how to use it. Explain documented
choices and constraints, validation/error states, availability or feature flags if relevant.
Separate implemented behavior from future plans. Cover existing behavior/defaults affected by the
feature and the acceptance scenarios actually exercised. No API section unless a contract changed.

Illustrative shape; the design reason here must be present in actual evidence before reuse:

```markdown
## 概要
一覧の選択項目をCSVで保存できるようにする。画面を見ながら手で転記する作業を減らす。

## 利用方法・変更内容
- 一覧で項目を選択し、「CSVで保存」を押す。
- 選択した項目のみを出力する。未選択時は保存ボタンを無効にする。

## 設計理由・制約
要件に従い、全件ではなく選択項目を出力する。CSVの列順は画面の列順に合わせる。
このPRにはファイルの再取り込み機能を含まない。

## 確認
選択状態と出力処理をコードで確認。実際のダウンロードと文字化けの確認は未実行。
```

## Mixed and less obvious changes

A feature with a bug fix can use one purpose section and separate behavior bullets with corresponding
checks. A UI feature plus API change needs both user-flow and contract examples. Tests, generated
files and docs supporting a feature are supporting changes, not separate goals unless they alter
their own consumer contract. Classify by what changes for users/operators/developers; do not rely
solely on changed extensions, branch names or Conventional Commit prefixes.

For a pure refactor, specify the invariant and why the dependency/structure changes. For a
performance change without measurements, explain the mechanism and label the effect unmeasured.
For a migration, expose ordering and irreversibility before ordinary implementation details.

## Verification claims

Record a command/scenario, cwd/environment, tested revision, result and relevant limitation. Existing
CI evidence must identify its run URL and SHA; stale CI is not verification of the current head.
A user's report can be attributed as reported evidence, not presented as a command you executed.
No rerun merely to reconfirm a user-reported failure. Distinguish schema checks from runtime checks,
local observations from production status, and “not run” from “passed”. Do not check template boxes
because the relevant test file exists or because compilation would plausibly succeed.

Do not manufacture new tests just to produce a PR checklist. Use existing permitted commands where
appropriate. For docs-only work, relevant render/link/usage inspection may suffice; explain the
scope rather than reporting that the whole product test suite passed.

## Writing and presentation

- Lead with purpose and result; explain details in reviewer reading order.
- Use exact names for methods, fields, statuses and commands. Avoid generic “改善した” without a change.
- State important facts inline even when linking an issue; inaccessible links should not hide intent.
- Use a table for comparable before/after values, a diagram only for a real flow/state/dependency
  question, and a screenshot only for a visual change. Do not show the same information twice.
- Put large endpoint examples in labelled Markdown `<details>` blocks if it improves scanning;
  every affected operation must still have a visible inventory entry and accessible full examples.
- Keep examples copyable and private-data-free. Do not embed local absolute paths or unreleased
  private identifiers in the publishable body. Never upload attachments without explicit permission.
- Delete filler, empty optional headings and file-by-file narration that adds no behavioral meaning.

## Primary sources

- [GitHub: Helping others review your changes](https://docs.github.com/en/pull-requests/concepts/helping-others-review-your-changes): focused changes, context, self-review and security risk.
- [Google: Writing good CL descriptions](https://google.github.io/eng-practices/review/developer/cl-descriptions.html): what/why, design context and a lasting record.
- [GitHub: PR templates](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository): supported locations and multiple templates.
- [GitHub: Linking a PR to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue): links versus closing keywords and default-branch behavior.

These sources inform selection; they do not require every section for every PR.
