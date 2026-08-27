---
name: finishing-a-development-branch
description: >-
  実装が完了し、この作業をどう取り込むか決めるときに使う。
  テストと検証を通し、環境を判定し、選択肢を提示し、選ばれた処理を実行して後始末する。
  「終わった」「マージしたい」「PR にしたい」の入口。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 開発ブランチを仕上げる

## 概要

**中核**: 検証を通す → 環境を判定する → 選択肢を提示する → 選ばれた処理を実行する → 後始末する。

**開始時に宣言する**: 「finishing-a-development-branch を使ってこの作業を仕上げる」

## Step 1: 検証を通す

1. プロジェクトのテストスイートを実行する（`npm test` / `cargo test` / `pytest` / `go test ./...`）
2. `/verify` を実行する（ビルド、型チェック、lint、テスト、デバッグ文の監査をまとめて回す）
3. `/pre-commit-review` を実行する（セキュリティとコード品質の確認）

**失敗があれば、そこで止めて報告する。** メニューは緑になってから出す。

```
テストが失敗している（<N> 件）。仕上げる前に直す必要がある:

[失敗の内容]
```

`/pre-commit-review` が CRITICAL を返した場合も同様に止める。

**すべて通ったら** Step 2 へ進む。

未コミットの変更が残っているなら、Conventional Commits（`<type>: <description>`、1 コミット 1 論理変更）でコミットしてから進む。

## Step 2: 環境を判定する

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# Step 5 でディレクトリを移動する前に、ここで取っておく
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

どのメニューを出すか、後始末をどうするかが決まる。

| 状態 | メニュー | 後始末 |
|---|---|---|
| `GIT_DIR == GIT_COMMON`（通常のリポジトリ） | 3 択 | worktree は無い |
| `GIT_DIR != GIT_COMMON`、ブランチ上 | 3 択 | 出自に応じて（Step 6） |
| `GIT_DIR != GIT_COMMON`、detached HEAD | 2 択（merge 無し） | 外部管理。そのまま残す |

## Step 3: base ブランチを決める

base ブランチはこの作業が分岐した元である。通常はプラン、会話、ブランチの upstream に書かれている。分からなければ聞く。

> 「このブランチは <推測> から分岐したと思うが、合っているか」

merge の前に確認する。誤った base への merge は取り消しが高くつく。

## Step 4: 選択肢を提示する

**通常のリポジトリ、およびブランチ上の worktree — この 3 択をそのまま出す**:

```
実装が完了した。どうするか。

1. <base-branch> へローカルで merge する
2. push して Pull Request を作る
3. ブランチをこのまま残す（自分で処理する）

どれにするか。
```

**detached HEAD — この 2 択をそのまま出す**:

```
実装が完了した。detached HEAD（外部管理のワークスペース）にいる。

1. 新しいブランチとして push して Pull Request を作る
2. このまま残す（自分で処理する）

どれにするか。
```

メニューはここに書いてある通りに出す。**作業を破棄する選択肢はメニューに入れない。** 破棄はユーザーが明示的に求めたときだけ行う（後述）。答えを待つ。取り込みの判断はユーザーのものである。

## Step 5: 選ばれた処理を実行する

### 選択肢 1: ローカルで merge する

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# 先に merge する。成功を確認してから何も消さない
git checkout <base-branch>
git pull
git merge <feature-branch>

# merge 結果でテストを回す
<test command>
```

merge 結果でテストが落ちたら、止めて worktree とブランチをそのまま残し、調査する。push していないので merge はローカルで、取り消せる。

merge 結果が緑になったら worktree を後始末し（Step 6）、ブランチを削除する。

```bash
git branch -d <feature-branch>
```

### 選択肢 2: push して PR を作る

```bash
git push -u origin <feature-branch>
# detached HEAD からは remote 側のブランチ名を指定する:
# git push origin HEAD:refs/heads/<new-branch>
```

そのうえで <base-branch> に対して PR を作る。forge の CLI があればそれを使い、無ければ push 時に表示される作成 URL を使う。リポジトリに PR テンプレートや慣習があればそれに従う。URL をユーザーに報告する。

**worktree は残す。** PR のフィードバック対応はそこで行う。

### 選択肢 3: このまま残す

報告する: 「ブランチ <name> を残す。worktree は <path> にある」

### ユーザーが破棄を求めた場合

この経路は、作業を捨てるという明示的な要求への応答としてだけ存在する。先に確認する。

```
次を完全に削除する:
- ブランチ <name>
- コミット: <commit-list>
- worktree: <path>

確認のため 'discard' と入力してほしい。
```

**その通りの語**を待つ。届いたら:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

worktree を後始末し（Step 6）、ブランチを強制削除する。

```bash
git branch -D <feature-branch>
```

## Step 6: ワークスペースの後始末

**選択肢 1 と、確認済みの破棄でだけ実行する。** 選択肢 2 と 3 は常に worktree を残す。どちらの呼び出し元も既にメインリポジトリのルートへ移動している（worktree の削除は worktree の外から実行する必要がある）。Step 2 で取った `GIT_DIR` / `GIT_COMMON` / `WORKTREE_PATH` を使う。

**`GIT_DIR == GIT_COMMON` の場合**: 通常のリポジトリ。後始末する worktree は無い。

**`WORKTREE_PATH` が `.worktrees/` または `worktrees/` の下にある場合**: このスキルの流れで作った worktree なので、こちらが後始末する。

```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune  # 古い登録の掃除
```

worktree 内の `_cellfusion/`（SDD の ledger・brief・report・review package）も一緒に消える。無視されたファイルは dirty 判定に出ないので警告は出ない。残したいものがあれば削除前に worktree の外へ写す。

**`$HERDR_ENV` が `1` で、`WORKTREE_PATH` が `~/.herdr/worktrees/` の下にある場合**: herdr が workspace として作った worktree である。先に workspace を畳んでから worktree を消す。

```bash
ws=$(herdr worktree list --cwd "$WORKTREE_PATH" \
  | jq -r --arg p "$WORKTREE_PATH" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
if [ -n "$ws" ]; then
  herdr worktree remove --workspace "$ws" --force
fi
```

`ws` が空なら workspace は既に無いので、この手順を飛ばして `git branch` の削除へ進む。`herdr worktree remove` は worktree のディレクトリも一緒に消すので、上の `git worktree remove` は不要（実行すると対象が既に無く失敗するので呼ばない）。

**それ以外**: ホスト環境が所有するワークスペースなのでそのまま残す。ハーネスに worktree 退出用のツールがあればそれを使う。

## chezmoi リポジトリの場合

`chezmoi apply` は **chezmoi の source directory**（`chezmoi source-path` が返すパス）を読む。worktree で実装した内容は、メインチェックアウトへ merge するまで apply に反映されない。

順序:

1. worktree で実装してコミットする
2. 選択肢 1 でメインチェックアウトへ merge する
3. `chezmoi diff` で反映内容を確認する
4. **`chezmoi apply` はユーザーの明示的な許可を得てから実行する**

設定を実際に反映して動作確認したい場合は、この順序を必ず守る。

## 早見表

| 選択肢 | merge | push | worktree を残す | ブランチ削除 |
|---|---|---|---|---|
| 1. ローカル merge | する | - | - | する |
| 2. PR を作る | - | する | 残す | - |
| 3. このまま残す | - | - | 残す | - |
| 破棄（明示要求時のみ） | - | - | - | する（強制） |

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「さっきテストが通った」 | これから取り込むツリーでスイートを回す。緑は回したツリーについてしか証明しない |
| 「明らかに merge してほしいはずだ」 | 取り込みの判断はユーザーのもの。メニューを出して待つ |
| 「この機能はもう不要そうなので破棄を提案する」 | メニューは書いてある通りで完結している。破棄はユーザーがそう言ったときだけ |
| 「『うん、消していいよ』は確認になる」 | 削除を許可するのは `discard` と入力されたときだけ |
| 「PR を出したので worktree は不要だ」 | PR のフィードバックはその worktree で直す。取り込まれるまで残す |
| 「この worktree は古そうなので一緒に消す」 | 後始末するのは `.worktrees/` `worktrees/` 配下と、herdr が作った `~/.herdr/worktrees/` 配下だけ。他はホストのもの |
| 「merge 結果の失敗はたぶん flaky」 | merge 結果の失敗は全部を止める。ブランチと worktree はそのまま調査する |
| 「base はどうせ main だ」 | 分岐元を確認するか聞く。誤った base への merge は取り消しが高くつく |
| 「push が拒否されたので force-push する」 | 拒否は remote が進んだという意味。調査する。force-push はユーザーの明示要求時のみ |
