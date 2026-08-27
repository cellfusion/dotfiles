# Refactor Clean

デッドコードの検出と安全な削除を行います。

## 引数

- `scan` — 検出のみ（デフォルト）
- `clean` — 検出後、SAFE カテゴリのものを自動削除
- `report` — 詳細レポートを出力

## 手順

### 1. プロジェクト検出

ツールチェインを特定してください：
- **TypeScript/JavaScript**: `package.json` の存在を確認
- **Rust**: `Cargo.toml` の存在を確認

### 2. ツールベースの検出

利用可能なツールがあれば使用：
- **TypeScript**: `npx knip` または `npx ts-prune`（インストール済みの場合）
- **Rust**: `cargo +nightly udeps`（インストール済みの場合）

ツールが未インストールの場合は、手動分析にフォールバックしてください。

### 3. 手動分析

Grep と Glob を使用して以下を検出：

#### エクスポートされているが未使用
- `export` されているが他ファイルから import されていない関数・型・定数
- `pub` だが crate 内で参照されていないアイテム（Rust）

#### 未使用コード
- 未使用の変数・関数（コンパイラ警告を確認）
- コメントアウトされたコードブロック
- 空のファイル・モジュール

#### 依存関係
- `package.json` の未使用 dependencies
- `Cargo.toml` の未使用 dependencies

### 4. 分類

検出結果を3段階に分類：

- **SAFE** — 確実に未使用。参照ゼロ、副作用なし
- **CAUTION** — おそらく未使用だが、動的参照やリフレクションの可能性あり
- **DANGER** — エントリポイント、プラグイン登録、副作用のある初期化コードなど

### 5. レポート

```
## Refactor Clean Report

### SAFE (auto-removable)
- ファイル:行 - 説明

### CAUTION (manual review needed)
- ファイル:行 - 説明

### DANGER (do not auto-remove)
- ファイル:行 - 説明

### Summary
- SAFE: N items
- CAUTION: N items
- DANGER: N items
```

`clean` モードの場合は、SAFE カテゴリのみを削除し、各削除を個別コミットとして提案してください。

$ARGUMENTS
