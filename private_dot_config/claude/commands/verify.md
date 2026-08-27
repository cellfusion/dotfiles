# Verify

プロジェクトの健全性を一括検証します。

## 引数

- `quick` — ビルドと型チェックのみ
- `full` — 全チェック実行（デフォルト）
- `pre-commit` — コミット前チェック（ビルド、型、lint、セキュリティ）
- `pre-pr` — PR作成前の完全チェック（full + console.log監査）

## 手順

以下のステップを順番に実行してください。引数に応じてスキップするステップがあります。

### 1. プロジェクト検出

プロジェクトルートを特定し、使用されているツールチェインを検出してください：
- `package.json` → Node.js/TypeScript プロジェクト
- `Cargo.toml` → Rust プロジェクト
- 両方存在する場合は両方を対象にする

### 2. ビルド確認（全モード）

- **Node.js**: `npm run build` または `bun run build`（package.json の scripts を確認）
- **Rust**: `cargo build`

ビルドエラーがあれば、ここで停止してエラーを報告してください。

### 3. 型チェック（全モード）

- **TypeScript**: `npx tsc --noEmit`
- **Rust**: ビルド時に実施済み

### 4. Lint（full, pre-commit, pre-pr）

- **Node.js**: `npx biome check .` または `npx eslint .`（プロジェクトの設定に従う）
- **Rust**: `cargo clippy -- -D warnings`

### 5. テスト実行（full, pre-pr）

- **Node.js**: `npm test` または `bun test`
- **Rust**: `cargo test`

テスト失敗があれば報告してください。

### 6. console.log / dbg! 監査（pre-pr）

ソースコード内の以下を検索し、意図的でないものを報告：
- `console.log`, `console.debug`, `console.warn`（テストファイル以外）
- `dbg!`, `println!`（テストモジュール以外）

### 7. Git Status

`git status` と `git diff --stat` を表示して、現在の変更状況をまとめてください。

## 出力

各ステップの結果を以下の形式でまとめてください：

```
## Verify Results (mode)
- [ ] Build: PASS/FAIL
- [ ] Type Check: PASS/FAIL
- [ ] Lint: PASS/FAIL (N issues)
- [ ] Tests: PASS/FAIL (N passed, M failed)
- [ ] Debug Statements: N found
- [ ] Git Status: clean/N files changed
```

$ARGUMENTS
