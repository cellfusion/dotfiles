# Defense-in-Depth Validation

## 概要

不正なデータが原因のバグを直すとき、1 箇所に検証を足せば十分に思える。しかしその 1 箇所は、別の実行経路・リファクタリング・mock によって迂回されうる。

**中核**: データが通るすべての層で検証する。バグを構造的に起こりえなくする。

## なぜ複数の層か

1 箇所の検証は「バグを直した」。複数の層は「バグを起こりえなくした」。

層ごとに捕まえるものが違う。

- 入口の検証はほとんどのバグを捕まえる
- ビジネスロジックの検証はエッジケースを捕まえる
- 環境ガードは文脈固有の危険を防ぐ
- デバッグログは他の層が抜けたときに効く

## 4 つの層

### 層 1: 入口の検証

**目的**: API 境界で明らかに不正な入力を弾く

```typescript
function createProject(name: string, workingDirectory: string) {
  if (!workingDirectory || workingDirectory.trim() === '') {
    throw new Error('workingDirectory cannot be empty');
  }
  if (!existsSync(workingDirectory)) {
    throw new Error(`workingDirectory does not exist: ${workingDirectory}`);
  }
  if (!statSync(workingDirectory).isDirectory()) {
    throw new Error(`workingDirectory is not a directory: ${workingDirectory}`);
  }
}
```

### 層 2: ビジネスロジックの検証

**目的**: この操作にとってデータが意味を成すことを保証する

```typescript
function initializeWorkspace(projectDir: string, sessionId: string) {
  if (!projectDir) {
    throw new Error('projectDir required for workspace initialization');
  }
}
```

### 層 3: 環境ガード

**目的**: 特定の文脈で危険な操作を防ぐ

```typescript
async function gitInit(directory: string) {
  // テスト中は temp ディレクトリ外での git init を拒否する
  if (process.env.NODE_ENV === 'test') {
    const normalized = normalize(resolve(directory));
    const tmpDir = normalize(resolve(tmpdir()));

    if (!normalized.startsWith(tmpDir)) {
      throw new Error(
        `Refusing git init outside temp dir during tests: ${directory}`
      );
    }
  }
}
```

### 層 4: デバッグ計測

**目的**: 事後分析のために文脈を残す

```typescript
async function gitInit(directory: string) {
  const stack = new Error().stack;
  logger.debug('About to git init', {
    directory,
    cwd: process.cwd(),
    stack,
  });
}
```

## 適用手順

バグを見つけたら:

1. **データの流れを追う** — 不正な値はどこで生まれ、どこで使われるか
2. **通過点をすべて洗い出す** — データが通る点を列挙する
3. **各層に検証を足す** — 入口、ビジネスロジック、環境、デバッグ
4. **各層をテストする** — 層 1 を迂回してみて、層 2 が捕まえることを確認する

## 実例

バグ: 空の `projectDir` によりソースコードで `git init` が走った

**データの流れ**:

1. テストのセットアップ → 空文字列
2. `Project.create(name, '')`
3. `WorkspaceManager.createWorkspace('')`
4. `git init` が `process.cwd()` で走る

**追加した 4 層**:

- 層 1: `Project.create()` が空でない・存在する・書き込めることを検証
- 層 2: `WorkspaceManager` が projectDir が空でないことを検証
- 層 3: `WorktreeManager` がテスト中の tmpdir 外 git init を拒否
- 層 4: git init 前にスタックトレースを記録

**結果**: 全テストが通り、バグを再現できなくなった。

## 要点

4 つの層はすべて必要だった。検証中、各層が他の層の取りこぼしを捕まえた。

- 別の実行経路が入口の検証を迂回した
- mock がビジネスロジックの検査を迂回した
- プラットフォーム固有のエッジケースには環境ガードが要った
- デバッグログが構造的な誤用を特定した

**検証を 1 箇所で止めない。** すべての層にチェックを入れる。
