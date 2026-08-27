# Rust Development Assistant

Rust開発を支援するスキルです。

## 提供機能

### コード品質チェック
以下のコマンドを実行してコードの品質を確認します：
- `cargo fmt --check` - フォーマットチェック
- `cargo clippy -- -D warnings` - lint警告チェック
- `cargo test` - テスト実行

### 開発ワークフロー

1. **ビルド確認**: `cargo build`
2. **フォーマット適用**: `cargo fmt`
3. **lint修正**: `cargo clippy --fix --allow-dirty`
4. **テスト実行**: `cargo test`

## ベストプラクティス

- `unwrap()` より `?` 演算子や `expect()` を推奨
- エラー型には `thiserror` または `anyhow` を使用
- 必要に応じて `#[derive(Debug, Clone)]` を追加
- ドキュメントコメント `///` を公開APIに追加

## 使用方法

引数にタスクを指定してください。例：
- `/rust-dev 新しいモジュールを作成`
- `/rust-dev エラーハンドリングを改善`
- `/rust-dev テストを追加`

$ARGUMENTS
