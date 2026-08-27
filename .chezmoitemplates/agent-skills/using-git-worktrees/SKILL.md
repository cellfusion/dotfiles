---
name: using-git-worktrees
description: >-
  実装プランの実行前や、現在のワークスペースから隔離したい機能開発の前に使う。
  既に隔離されているかを検出し、必要なら worktree を作って
  依存インストールとベースラインテストまで済ませる。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 隔離ワークスペースを用意する

## 概要

実装は隔離されたワークスペースで行う。ハーネスに worktree 用のツールがあればそれを使い、無いときだけ `git worktree` に落とす。

**中核**: まず既に隔離されているかを検出する。次にネイティブツールを使う。最後に git へ落とす。ハーネスと喧嘩しない。

**開始時に宣言する**: 「using-git-worktrees を使って隔離ワークスペースを用意する」

## Step 0: 既に隔離されているかを検出する

**何かを作る前に、今いる場所が既に隔離ワークスペースかを確認する。**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**submodule ガード**: `GIT_DIR != GIT_COMMON` は submodule の中でも真になる。「既に worktree にいる」と結論する前に submodule でないことを確認する。

```bash
# パスが返るなら worktree ではなく submodule。通常リポジトリとして扱う
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**`GIT_DIR != GIT_COMMON`（かつ submodule でない）場合**: 既に linked worktree の中にいる。もう 1 つ worktree を作ってはならない。下の herdr の確認と報告を済ませてから Step 2 へ進む。

**herdr 管理下（`$HERDR_ENV` が `1`）の場合**、その worktree が workspace として開かれているかも確認する。開かれていない worktree は端末を持たず、中で動くエージェントの作業が人間から見えない。`herdr worktree list` が失敗したらこの確認を飛ばして先へ進む。

```bash
ws=$(herdr worktree list --cwd "$(pwd -P)" \
  | jq -r --arg p "$(pwd -P)" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
```

`ws` が空なら、workspace として開く。

```bash
out=$(herdr worktree open --path "$(pwd -P)" --no-focus)
ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
```

既に開かれていた場合は `herdr worktree list` から取った `ws` をそのまま使う。

`$HERDR_ENV` が `1` でないときはこの確認を丸ごと飛ばす。

ブランチの状態と併せて報告する。herdr 管理下なら workspace ID（`$ws`）も添える。

- ブランチ上: 「既に隔離ワークスペース `<path>`（ブランチ `<name>`、workspace `<id>`）にいる」
- detached HEAD: 「既に隔離ワークスペース `<path>` にいる（detached HEAD、外部管理）。ブランチ作成は finish 時に行う」

報告が済んだら Step 2 へ進む。

**`GIT_DIR == GIT_COMMON`（または submodule）の場合**: 通常のチェックアウトにいる。Step 1 へ進む。

## Step 1: 隔離ワークスペースを作る

手段は 3 つ。この順に試す。

### 1a. herdr の worktree（herdr 管理下では最優先）

`$HERDR_ENV` が `1` なら、これを最初に試す。

```bash
out=$(herdr worktree create --workspace "$HERDR_WORKSPACE_ID" --branch "<branch>" --base HEAD --no-focus)
path=$(printf '%s' "$out" | jq -r '.result.worktree.path')
ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
cd "$path"
```

herdr で作った worktree は人間が入れる workspace になり、そこで動くエージェントの作業ツリーと進捗が外から見える。ハーネス側のツールで作った worktree は端末を持たないので、これを先に使う。

- **`--workspace` を必ず付ける。** 省くとユーザーがフォーカスしている workspace が基準になる
- **`--path` は渡さない。** herdr が `~/.herdr/worktrees/<repo>/<branch>` に作る。1a で作るこの worktree 自体は下の「ディレクトリの決定」と ignore の確認は要らない。ただし SDD の波は `.worktrees/` を使うので、`git check-ignore` は Step 2 の前に 1 度通す
- `path` か `ws` が空か `null` なら委譲は成立しない。`ws` が非空なら `herdr worktree remove --workspace "$ws" --force` で片付けてから 1b へ落ちる。`ws` が空か `null` なら片付けられないので、その旨も添えて報告してから 1b へ落ちる

報告にはパスとブランチに加えて workspace ID も載せる。下の「`.worktrees/` の ignore を確認する（SDD 用）」を済ませてから Step 2 へ進む。

### 1b. ネイティブの worktree ツール

`EnterWorktree` のようなツール、`/worktree` コマンド、`--worktree` フラグが使えるならそれを使う。下の「`.worktrees/` の ignore を確認する（SDD 用）」を済ませてから Step 2 へ進む。

ネイティブツールは配置・ブランチ作成・後始末を自分で管理する。ネイティブツールがあるのに `git worktree add` を使うと、ハーネスから見えない状態を作ることになる。

1b が使えないときだけ 1c へ進む。

### 1c. git worktree で作る

#### ディレクトリの決定

この優先順で決める。ユーザーの明示指定が常に最優先。

1. **指示に worktree ディレクトリの指定があるか確認する**。あれば聞かずにそれを使う
2. **プロジェクト内の既存 worktree ディレクトリを探す**:
   ```bash
   ls -d .worktrees 2>/dev/null     # 優先（隠しディレクトリ）
   ls -d worktrees 2>/dev/null      # 代替
   ```
   見つかればそれを使う。両方あれば `.worktrees` を採る
3. **他に手掛かりが無ければ**、プロジェクトルートの `.worktrees/` を既定にする

#### 安全確認（プロジェクト内ディレクトリの場合のみ）

**1c で worktree を作る前に、そのディレクトリが ignore されていることを必ず確認する**:

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**ignore されていない場合**: `.gitignore` に追加してコミットしてから進む。worktree の中身がまるごとリポジトリに入るのを防ぐため。

#### 作成

```bash
path="$LOCATION/$BRANCH_NAME"
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

**sandbox で失敗した場合**: `git worktree add` が権限エラーで落ちたら、sandbox に阻まれたので現在のディレクトリで作業する旨をユーザーに伝える。セットアップとベースラインテストはその場で行う。

### `.worktrees/` の ignore を確認する（SDD 用）

subagent-driven-development のタスク波は、隔離ワークスペースをどの手段で作ったかによらず常に `.worktrees/` を使う（`git worktree add "<repo-root>/.worktrees/task-<N>"`）。1a・1b を通った場合、または 1c で `worktrees`（代替）を選んだ場合は、`.worktrees/` の ignore をまだ確認していない。Step 2 の前に 1 度確認する。

```bash
git check-ignore -q .worktrees 2>/dev/null || {
  echo ".worktrees/" >> .gitignore
  git add .gitignore
  git commit -m "chore: ignore .worktrees/ for SDD task waves"
}
```

1c で `.worktrees/` を選んで既に確認済みの場合はここを飛ばしてよい。

## Step 2: プロジェクトのセットアップ

**リポジトリに `.config/wt.toml` があるなら worktrunk に任せる。** 追跡外ファイルのコピー（`.worktreeinclude` に基づく）と依存インストールがそこに書かれている。

```bash
if [ -f "$(git rev-parse --show-toplevel)/.config/wt.toml" ] && command -v wt >/dev/null 2>&1; then
  wt hook pre-start
fi
```

`wt hook pre-start` は worktree を誰が作ったかを問わず動く。herdr で作っても `git worktree add` で作っても同じ結果になる。**`pre-` を使う。** `post-` は背後で走って即座に戻るので、Step 3 のベースラインテストがセットアップ未完了の作業ツリーに当たる。

**`.config/wt.toml` が無いリポジトリ**では、検出して該当するものを実行する。

```bash
if [ -f package.json ]; then npm install; fi
if [ -f Cargo.toml ]; then cargo build; fi
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi
if [ -f go.mod ]; then go mod download; fi
```

`.env` などの追跡外ファイルが要るのに毎回手で配っているなら、リポジトリに `.worktreeinclude` と `.config/wt.toml` を置くようユーザーに提案する。以降その手作業は消える。

## Step 3: ベースラインを確認する

ワークスペースがきれいな状態から始まることをテストで確認する。

```bash
npm test / cargo test / pytest / go test ./...
```

**失敗した場合**: 失敗内容を報告し、進めるか調べるかをユーザーに確認する。

**通った場合**: 準備完了を報告する。

```
worktree: <full-path>
テスト: <N> passed, 0 failed
<feature-name> の実装を開始できる
```

テストが存在しないプロジェクト（dotfiles、設定リポジトリなど）では、テストの代わりに `git status` がきれいであることを確認する。

## chezmoi リポジトリでの注意

`chezmoi apply` はチェックアウトしているブランチではなく、**chezmoi の source directory（`chezmoi source-path` が返すパス、既定は `~/.local/share/chezmoi`）を読む**。worktree（例 `~/.local/share/chezmoi/.worktrees/feat-x`）で編集しても、そのままでは apply に反映されない。

- worktree で実装し、コミットまで済ませる
- メインチェックアウトへマージしてから `chezmoi diff` / `chezmoi apply` で反映する（apply はユーザーの明示許可を得てから）

この順序を守らないと、動作確認したつもりが古い内容を apply することになる。

## 早見表

| 状況 | 対応 |
|---|---|
| 既に linked worktree の中 | 作成しない（Step 0） |
| worktree の中だが workspace として開かれていない | `herdr worktree open` で開く（Step 0） |
| submodule の中 | 通常リポジトリとして扱う（Step 0 のガード） |
| herdr 管理下（`HERDR_ENV=1`） | `herdr worktree create` で作る（Step 1a） |
| ネイティブ worktree ツールあり | それを使う（Step 1b） |
| ネイティブツール無し | git worktree で作る（Step 1c） |
| `.worktrees/` がある | それを使う（ignore を確認） |
| `worktrees/` がある | それを使う（ignore を確認） |
| 両方ある | `.worktrees/` を採る |
| どちらも無い | 指示を確認し、既定は `.worktrees/` |
| ディレクトリが ignore されていない | `.gitignore` に追加してコミット |
| 作成が権限エラー | sandbox とみなし現ディレクトリで作業 |
| ベースラインテストが落ちる | 失敗を報告して判断を仰ぐ |

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「見るからに worktree ではない」 | Step 0 を実行する。ハーネスが作った隔離も submodule も目視では判別できない |
| 「`git worktree add` でも同じものができる」 | できるのは作業ツリーだけで、端末が無い。中で動くエージェントの作業は人間から見えない |
| 「`git worktree add` のほうが早い」 | ネイティブツールは配置・ブランチ・後始末を管理する。迂回するとハーネスから見えない状態が残る |
| 「worktree ディレクトリはどうせ ignore 済みだ」 | `git check-ignore` を実行する。ignore されていなければツリー全部がリポジトリに入る |
| 「新しいワークスペースだからベースラインは通る」 | 汚れたベースラインは以降のすべての失敗を曖昧にする。先に実行する |
| 「chezmoi リポジトリでも worktree で apply できる」 | apply は source directory を読む。マージしてからでないと反映されない |
