---
name: handoff
description: >-
  context 逼迫時に、新しい herdr pane でクリーンな後継 Claude セッションを起動し、
  引き継ぎドキュメントを渡して作業を継続させる手順。
  context 使用率が目安 60% を超えたとき、または auto-compact / context 上限の警告が出たときに使う。
  HERDR_ENV=1 のときのみ有効。
---

# Session Handoff

context が逼迫してきたら、劣化する前に**新しい herdr pane でクリーンな後継セッションを起動し、引き継ぎドキュメントを渡してバトンを渡す**。以降の作業は後継セッションが継続し、現行セッションは終了する。

## 前提と起動判断

- **前提**: herdr 管理下（`HERDR_ENV=1`）のときのみ。未設定なら通常の auto-compact に任せ、この手順は実行しない。Paseo を含め、`HERDR_ENV` が `1` でない環境で herdr を起動してはならない
- **目安: context 使用率が約 60% を超えたと判断したとき**。ただし Claude は正確な使用率を取得できないため、これは自己判断の目安。**auto-compact / context 上限の警告が出たら、それは確実に「今やるべき」タイミング**
- 逼迫していても、**現在の atomic な作業ステップの途中では引き継がない**。編集途中なら区切りまで完了させるか、未コミット変更を引き継ぎドキュメントに明記してから行う

## 手順

1. **引き継ぎドキュメントをファイルに書く**（argv に詰めない）。保存先は `~/.config/claude/handoffs/`（初回は `mkdir -p`）、ファイル名 `handoff-$(date +%Y%m%d-%H%M%S).md`。絶対パスを後続 3 で渡す。**self-contained** であること — 後継セッションはこの会話の記憶を持たず、CLAUDE.md・メモリファイル・この引き継ぎドキュメントだけが頼り。最低限:
   - タスクの目的 / ゴール
   - 完了済みの内容
   - 次にやるステップ（順序付き）
   - 関連ファイルパス・重要な関数（`file_path:line`）
   - 決定事項とその理由 / 却下した選択肢
   - ハマりポイント・注意
   - git 状態（branch、未コミット/stash の有無）
   - 関連メモリ（`[[name]]`）へのリンク
   - **skip-permissions で無人継続するため、破壊的・不可逆操作は「要ユーザー確認」と明記**して後継の暴走を防ぐ

2. **自分の pane の隣に新規 pane を作る**（`$HERDR_PANE_ID` 基準・同じ cwd）。`--current` は使わない（ユーザーのフォーカス pane 基準になり別ワークスペースに開くため）:

   ```bash
   herdr pane split "$HERDR_PANE_ID" --direction down --cwd "$PWD" --no-focus
   # 返る pane_id を <new_pane> とする
   ```

3. **後継セッションを起動**（`CLAUDE_CONFIG_DIR` は `HERDR_SESSION` から zshrc で解決されるため、同一セッション内の新規 pane でも維持される。無人継続なので skip フラグは明示する）:

   ```bash
   herdr pane run <new_pane> "claude --dangerously-skip-permissions 'まず <引き継ぎドキュメントの絶対パス> を読み、そこに書かれたタスクを引き継いで続行せよ'"
   ```

4. **後継が起動したことを検証してから**現行を閉じる（起動失敗時は絶対に閉じない＝データ喪失防止）:

   ```bash
   herdr pane wait-output <new_pane> --match "<claude 起動プロンプトの目印>" --timeout 60000
   # もしくは herdr agent wait <new_pane> --until idle --timeout 60000
   ```

5. 検証 OK なら**現行セッションを終了**（自分の pane を閉じる＝現行 claude プロセス終了）:

   ```bash
   herdr pane close "$HERDR_PANE_ID"
   ```

## ガードレール

- **後継の起動確認が取れるまで現行を閉じない**。確認できなければ閉じずにユーザーへ報告する
- **起動直後の即再ハンドオフを避ける**。後継はハンドオフ直後に再度ハンドオフせず、最低 1 つの実作業ステップを完了してから次の逼迫判断を行う（連鎖は意図的だが空回りを防ぐ）
- 後継も CLAUDE.md を継承するので、再び逼迫すれば同様に引き継ぐ（意図的な連鎖）
