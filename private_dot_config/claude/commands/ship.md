# Ship

変更のレビュー → コミット → Linear 更新をワンステップで実行します。

## 引数

`$ARGUMENTS` — オプションフラグ

- `--no-linear`: Linear 更新をスキップ
- `--no-review`: レビューとverifyをスキップ（急ぎの場合のみ）

## 手順

### 1. 変更の確認

```bash
git status
git diff --stat
git diff --cached --stat
```

変更がなければ「コミットする変更がありません」と報告して終了。

### 2. レビュー（`--no-review` でスキップ）

以下を順番に実行:

1. 変更対象ファイルを読み、セキュリティ上の問題やコード品質の問題がないか確認
2. プロジェクト検出に基づき `/verify quick` 相当のチェックを実行（ビルド + 型チェック）

問題があれば報告し、修正するか続行するかユーザーに確認する。

### 3. コミット

1. `git diff` と `git diff --cached` で全変更内容を把握
2. Conventional Commits 形式でコミットメッセージを作成
3. 関連ファイルをステージング（`git add` は対象ファイルを明示指定）
4. コミット実行

### 4. Linear 更新（`--no-linear` でスキップ）

ブランチ名またはコミットメッセージから Linear イシューID を検出:

- ブランチ名パターン: `feat/PROJ-123-description`, `fix/PROJ-456`
- コミットメッセージパターン: `PROJ-123` 形式

検出された場合:
1. `mcp__claude_ai_Linear__get_issue` でイシューの現在のステータスを確認
2. コミット内容に基づきコメントを追加（`mcp__claude_ai_Linear__save_comment`）
3. ステータス変更が適切かユーザーに確認（自動でステータスは変更しない）

検出されなかった場合:
- スキップして報告

### 5. サマリー

```
## Ship Complete
- Commit: <hash> <message>
- Linear: <PROJ-123 updated/no issue detected/skipped>
```

$ARGUMENTS
