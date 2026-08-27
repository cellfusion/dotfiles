---
name: linear
description: >-
  Linear のプロジェクト管理（タスク作成・ドキュメント作成・イシュー管理）。
  ユーザーが「タスク」「イシュー」「Linear」「チケット」「起票」
  「ドキュメント」「仕様書」などのキーワードを使った際に自動起動。
  /linear で手動起動も可能。
---

# Linear プロジェクト管理スキル

Linear の MCP ツールを使い、プロジェクトごとのタスク管理・ドキュメント管理を行う。

## 使い方

### コンテキスト取得

操作対象のチーム・プロジェクトを特定する。毎回動的に取得すること。

1. `mcp__claude_ai_Linear__list_teams` でチーム一覧を取得
2. `mcp__claude_ai_Linear__list_projects` で対象チームのプロジェクト一覧を取得
3. 必要に応じて `mcp__claude_ai_Linear__get_project` で詳細（リソース含む）を取得

ユーザーが対象プロジェクトを明示していない場合は、一覧を提示して選択してもらう。

### タスク管理

#### 一覧・検索

```
mcp__claude_ai_Linear__list_issues
  - project: プロジェクト名
  - assignee: "me"（自分のタスク）
  - state: ステータス名でフィルタ（例: "In Progress", "Todo"）
  - query: キーワード検索
```

#### 詳細取得

```
mcp__claude_ai_Linear__get_issue
  - id: イシュー識別子（例: "PROJ-123"）
  - includeRelations: true（関連イシューも表示する場合）
```

#### 新規作成

作成前に `list_issues` で既存イシューを検索し、重複を避ける。

```
mcp__claude_ai_Linear__save_issue
  - title: イシュータイトル（必須）
  - team: チーム名（必須）
  - project: プロジェクト名
  - description: Markdown で記述
  - priority: 0=None, 1=Urgent, 2=High, 3=Normal, 4=Low
  - labels: ラベル名の配列
  - assignee: "me" または ユーザー名
```

ステータスとラベルの選択肢は事前に取得する:
- `mcp__claude_ai_Linear__list_issue_statuses` (team で指定)
- `mcp__claude_ai_Linear__list_issue_labels` (team で指定)

#### 更新

```
mcp__claude_ai_Linear__save_issue
  - id: イシュー識別子（例: "PROJ-123"）
  - state: 変更先ステータス名
  - assignee: 変更先担当者
  - priority: 変更先優先度
  （変更するフィールドのみ指定）
```

#### コメント追加

```
mcp__claude_ai_Linear__save_comment
  - issueId: イシュー識別子（例: "PROJ-123"）
  - body: Markdown で記述
```

### ドキュメント管理

#### 一覧・検索

```
mcp__claude_ai_Linear__list_documents
  - projectId: プロジェクト ID
  - query: キーワード検索
```

#### 新規作成

作成前に `list_documents` で既存ドキュメントを確認し、重複を避ける。

```
mcp__claude_ai_Linear__create_document
  - title: ドキュメントタイトル（必須）
  - content: Markdown で記述
  - project: プロジェクト名
```

#### 更新

```
mcp__claude_ai_Linear__update_document
  - id: ドキュメント ID（必須）
  - content: 更新後の Markdown
  - title: タイトル変更時のみ
```

## 自動起動ガイドライン

以下のような状況で、ユーザーに確認せず自動的に Linear を参照する:

- ユーザーが「タスク」「チケット」「イシュー」と言及した場合
- 作業中のコンテキストで Linear のプロジェクトやイシューが関連する場合
- 「起票して」「チケット切って」と依頼された場合

参照して関連するイシューが見つかった場合:
- イシューのタイトル・ステータス・担当者を要約して提示する

見つからなかった場合:
- 無言で続行する（検索したが見つからなかったことを報告しない）

## ワークフローのベストプラクティス

- **重複回避**: タスク作成前に既存イシューを検索する
- **Markdown**: description や content は Markdown で記述する
- **ステータス確認**: タスク作成・更新時は `list_issue_statuses` で有効なステータスを確認する
- **ラベル統一**: 新規ラベルを作る前に `list_issue_labels` で既存ラベルを確認する
- **プロジェクト紐付け**: タスクもドキュメントも必ず project を指定してプロジェクトに紐付ける
