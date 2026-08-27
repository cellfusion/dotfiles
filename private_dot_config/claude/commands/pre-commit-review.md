# Pre-Commit Review

コミット前のローカルコードレビューを実行します。セキュリティ脆弱性とコード品質を重点的にチェックします。

## 手順

### 1. 変更の取得

`git diff --cached` でステージングされた変更を取得してください。
ステージングされた変更がない場合は `git diff` で未ステージの変更を対象にします。

### 2. セキュリティチェック

以下の観点で変更をレビューしてください：

#### シークレット・認証情報
- ハードコードされたパスワード、APIキー、トークン
- `.env` ファイルや認証情報ファイルのコミット
- プライベートキーや証明書の混入

#### インジェクション脆弱性
- SQL インジェクション（プレースホルダ未使用のクエリ）
- コマンドインジェクション（ユーザー入力のシェル実行）
- XSS（サニタイズ未実施の出力）
- パストラバーサル（ユーザー入力のファイルパス使用）

#### その他
- 安全でない暗号化（MD5, SHA1 for passwords）
- CORS の過度な許可
- デバッグモードの本番残留
- 新規依存の既知脆弱性（lockfile 差分に新パッケージがあれば確認）

### 3. コード品質チェック

#### エラーハンドリング
- 空の catch ブロック
- エラーの握りつぶし（silent failures）
- 不適切なフォールバック

#### コードの健全性
- 未使用の import / 変数
- TODO / FIXME / HACK コメント（意図的か確認）
- マジックナンバー
- 過度に複雑な条件分岐

### 4. レポート出力

```
## Pre-Commit Review

### Security Issues
- [CRITICAL] ファイル:行 - 説明
- [WARNING] ファイル:行 - 説明

### Code Quality
- [ISSUE] ファイル:行 - 説明
- [SUGGESTION] ファイル:行 - 説明

### Summary
- Security: N critical, M warnings
- Quality: N issues, M suggestions
- Verdict: PASS / NEEDS ATTENTION / BLOCK
```

`CRITICAL` なセキュリティ問題がある場合は `BLOCK` を返し、コミットしないよう警告してください。

$ARGUMENTS
