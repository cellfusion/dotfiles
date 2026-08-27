---
name: tool-adopt
description: >-
  新しい CLI ツールの導入ワークフロー（調査・設定・chezmoi 管理・ドキュメント化）。
  ユーザーが「ツール導入」「新しいツール」「brew install」「設定追加」
  「tool-adopt」「インストール」などのキーワードを使った際に自動起動。
  /tool-adopt で手動起動も可能。
---

# ツール導入スキル

新しい CLI ツールを導入する際の定型ワークフローを自動化する。

## 使い方

### ワークフロー

1. **調査**: ツールの機能、設定ファイルの場所、主要なオプションを調べる
2. **インストール確認**: `brew info <tool>` や `which <tool>` でインストール状況を確認
3. **設定作成**: chezmoi ソース側に設定ファイルを作成
4. **シェル統合**: 必要に応じてエイリアスやラッパーを追加
5. **ドキュメント化**: `private_dot_config/docs/tools.md` の該当する表に追記する
6. **反映リマインド**: `chezmoi apply` を案内（自動実行しない）

### 設定ファイルの配置

chezmoi のパス規約に従う:

| 実際のパス | chezmoi ソース |
|-----------|---------------|
| `~/.config/tool/config.toml` | `private_dot_config/tool/config.toml` |
| `~/.tool.conf` | `dot_tool.conf` |
| `~/.local/bin/tool-wrapper` | `private_dot_local/bin/executable_tool-wrapper` |

### シェル統合

`.zshrc` にエイリアスや設定を追加する場合:
- chezmoi ソース: `private_dot_config/zsh/dot_zshrc`
- 既存の構成を確認し、適切な位置に追加

### Herdr 統合

Herdr のキーバインドに追加する場合:
- chezmoi ソース: `private_dot_config/herdr/config.toml`
- 既存の構成を確認し、適切な位置に追加
- キーバインドを変えたら `private_dot_config/docs/keybindings.md` も同じコミットで更新する

### television チャンネル統合

television のカスタムチャンネルを作成する場合:
- `private_dot_config/television/cable/` にチャンネル定義を追加
- 既存チャンネル（`custom-herdr-sessions.toml` など）を参考にする

## 自動起動ガイドライン

以下のような状況で自動的にこのスキルを起動する:

- ユーザーが新しい CLI ツールのインストールや設定について話題にした場合
- `brew install` コマンドを実行した、または実行しようとしている場合
- 「このツール使ってみたい」「設定どうする？」と言及した場合

自動で行うこと:
- ツールの公式ドキュメントを WebSearch で調査
- 既存の設定パターンを確認（chezmoi ソースの構成）

## 重要な注意事項

- **chezmoi apply は絶対に自動実行しない** — ユーザーの明示的な許可が必要
- chezmoi ソース側のみを編集する（`~/.local/share/chezmoi/` 配下）
- `.zshrc` や `herdr/config.toml` への変更は既存の構造を壊さないように注意
- 実行可能スクリプトは chezmoi で `executable_` プレフィックスを付ける

## 棚卸しへの記録

ツール導入が完了したら、`private_dot_config/docs/tools.md` に記録する。

- 導入経路に合った節（core / 言語・ビルド / macOS 専用 など）の表に 1 行足す
- マニフェストにも追加する。Homebrew なら `.chezmoitemplates/install/brewfile`、
  mise なら `private_dot_config/mise/config.toml`、npm なら
  `private_dot_config/install/npm-globals.txt`、cargo なら
  `private_dot_config/install/cargo-globals.txt`
- 表とマニフェストの整合は `bash tests/test-tools-doc.sh` が検証する
