---
name: dev-env
description: >-
  この環境固有の開発運用手順。Cloudflare のアカウント切り替え、
  1Password による CLI 認証とシークレット取得、AI 環境（herdr / Paseo）別の環境変数を扱う。
  デプロイ・認証情報・環境変数・アカウント切り替えに触れる作業の前に読む。
  /dev-env で手動起動も可能。
---

# 開発環境の運用手順

この機械（macOS / herdr / chezmoi）で実際にどう操作するかを記録する。汎用的な技術知見ではなく、この環境での手順を扱う。

## どの章を読むか

| 状況 | 読むファイル |
|---|---|
| Cloudflare にデプロイする。アカウントを切り替える | `references/cloudflare.md` |
| API トークンや認証情報が必要になる | `references/secrets.md` |
| AI 環境ごとに環境変数を変える | `references/herdr.md` |

## 共通の前提

- `~/.config` 配下の設定は chezmoi 管理下にある。`~/.local/share/chezmoi/` 側を編集し、`chezmoi apply` はユーザーが実行する。
- シークレットを平文でファイルに置かない。1Password から取る。
- 環境を変える操作（アカウント切り替え、プラグイン設定）を実行する前に、いま何が有効かを確認する。
