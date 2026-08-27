## worktree へ委譲する

承認 gate で「承認&worktree で委譲」が選ばれたときだけ実行する。worktree を新しい workspace として切り、その pane で起動した Claude セッションに実装を渡す。委譲元のこのセッションは pane を閉じずに待機する。

`$HERDR_ENV` が `1` であることは gate の判定で確認済みである。

### 1. plan を読み直す

プレビューは編集可で開いている。手編集はファイルにしか残らない。読み直した内容を正とする。

### 2. ブランチ名を決める

plan のファイル名から日付を落として `feat/<feature-name>` にする。`_cellfusion/plans/2026-08-14-worktree-handoff.md` なら `feat/worktree-handoff` である。

```bash
git rev-parse --verify "feat/<feature-name>" 2>/dev/null
```

終了ステータスが 0 なら同名のブランチが既にある。何も作らずに衝突を報告し、承認 gate へ戻る。

### 3. worktree を workspace として作り、応答から ID とパスを読む

1 つの bash 呼び出しで実行する。番号付きの手順でも、ここは 1 ブロックのまま崩さない。別々のシェル呼び出しに分けると `$out` が空になり、下の 3 つの値も空になる。

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --branch "feat/<feature-name>" \
  --base HEAD \
  --label "<feature-name>" \
  --no-focus)

ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id')
path=$(printf '%s' "$out" | jq -r '.result.worktree.path')
```

- **`--workspace` を必ず付ける。** 省くとユーザーがフォーカスしている workspace が基準になり、自分が動いている場所とは別に作られることがある
- **`--no-focus` を付ける。** 委譲元のセッションはこのあとも報告を続けるので、視線を奪わない
- **`--path` は渡さない。** herdr が `~/.herdr/worktrees/<repo>/<branch>` に作る。リポジトリの外なので、`.gitignore` を確認する必要が無い

3 つのどれかが空か `null` なら委譲は成立しない。`ws` が取れているなら `herdr worktree remove --workspace "$ws" --force` で片付ける。`ws` が取れていないなら片付けられないので、その旨も添えて報告し、承認 gate へ戻る。

以降の手順（step 5・6・失敗時の片付け）は、この `$out` / `$ws` / `$pane` / `$path` が後続の bash 呼び出しでは参照できない前提で進める。取れた値をリテラルで埋めて実行する。

### 5. その pane で Claude を起動する

```bash
herdr agent start "<agent-name>" --kind claude --pane "$pane"
```

- `<agent-name>` は feature-name をそのまま使う。`[a-z][a-z0-9_-]{0,31}` に収まらない文字は `-` に置き換え、32 文字を超えたら切り詰める
- **権限フラグを付けない。** 承認が要る場面ではその workspace で止まる。ユーザーがそこに入って判断する

### 6. 初回の指示を送る

```bash
herdr agent prompt "<agent-name>" "<指示>" --wait --timeout 120000
```

指示に入れるのは次の 4 点だけである。会話の履歴や経緯を貼らない。

- plan の**絶対パス**。**委譲元チェックアウト側のパスを渡す。** `_cellfusion/` は git 追跡外でブランチに乗らないため、worktree の中には存在しない
- このプランを subagent-driven-development で実装すること
- worktree は用意済みなので、新しく worktree を切らないこと
- この worktree のブランチ名

**タイムアウトは失敗ではない。** 委譲先が SDD を回し始めるのを `--wait` は待つので、`--timeout 120000` に達すること自体はよく起こる。timeout で返ってきても worktree は消さず、7 へ進む。

### 7. 報告して待機する

workspace ID、worktree の絶対パス、ブランチ名、agent 名を報告する。**自分の pane は閉じない。** ユーザーはこのセッションをそのまま次の作業に使える。

### 失敗したとき

**片付けの対象は step 2〜4（`herdr agent start` の前）で失敗した場合に限る。** この段までは worktree も workspace も委譲元だけが把握しており、他に依存者がいないので消してよい。片付けは `herdr worktree remove --workspace "$ws" --force` である。片付けたら報告し、承認 gate へ戻る。

**step 5（`herdr agent start`）以降で失敗した場合は worktree を消さない。** 委譲先の Claude セッションが既に起動している可能性があり、その worktree を強制削除すると稼働中のセッションごと消すことになる。workspace ID と worktree の絶対パスを添えて「委譲先は起動済みだが、初回指示の到達は未確認である」と報告し、承認 gate へ戻る。
