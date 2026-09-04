## mad-run の呼び方

`mad-run` は Paseo の CLI で複数のエージェントを並行・直列に走らせる。この節は MAD を呼ぶ
すべてのスキルが共有する。

### 前提

`paseo` が PATH にあること。無ければインストール済みと仮定して続行せず、実行方法が無いことを
報告して止まる。

```bash
command -v paseo
```

Paseo の daemon につながること。`paseo status` は daemon に届かなくても 0 で終わるので、
終了コードではなく出力を読む。`Local Daemon` が `running` で、`Connected Daemon` が
`reachable` であることを確かめる。

```bash
paseo status | grep -E '^(Local Daemon|Connected Daemon)'
```

`unresponsive` か `unreachable` なら、daemon が止まっているか、シェルが daemon に
つなげない。`paseo` の CLI は `127.0.0.1:6767` の daemon へ WebSocket でつなぐので、
ネットワークを遮断するサンドボックスの中では届かない。Codex の `auto` と `auto-review`
がこれに当たる。この場合は `mad-run` と `mad-runs` を `[retry-outside-sandbox]` で
サンドボックスの外に出して実行する。理由には「Paseo の daemon に接続してエージェントを
起動するため」と書く。

サンドボックスの外に出せないなら、MAD は使えない。実行方法が無いことを報告して止まる。

### 手順

**1. 本実行の前に dry-run を通す。**

```bash
~/.agents/skills/multi-agent-development/scripts/mad-run RECIPE --arg k=v --dry-run
```

引数の不足はここで返る。ノードごとに、役割・解決した provider・model・mode・プロンプトの
文字数が出る。失敗したら本実行へ進まず、出力をそのまま報告する。

**2. 本実行する。同期で待つ。**

```bash
~/.agents/skills/multi-agent-development/scripts/mad-run RECIPE --arg k=v
```

時間のかかるプロセスを別のところへ委譲する規約の例外にする。`mad-run` は run ディレクトリに
すべての成果物を残し、走っているエージェントは Paseo の daemon が持つので、シェルが死んでも
Paseo の側から `paseo ls` と `paseo stop` で追える。

ノード 1 つあたりの既定の実行上限は 1200 秒で、`--timeout <秒>` で全ノード共通に変えられる。
シェル実行ツール側のコマンドタイムアウトが既定より短いなら明示的に伸ばす。

**3. 長いレシピは切り離す。**

`implement` と `spike` は実装とレビューを何ラウンドも回すので、シェル実行ツールの
コマンドタイムアウトに先に当たる。`--detach` を付けると run id だけが返る。

```bash
~/.agents/skills/multi-agent-development/scripts/mad-run implement \
  --arg 'requirements=要件' --detach
```

進行は `mad-runs` で追う。

```bash
~/.agents/skills/multi-agent-development/scripts/mad-runs ls
~/.agents/skills/multi-agent-development/scripts/mad-runs show RUN_ID
```

`--detach` と `--dry-run` は同時に渡せない。同時に渡すと 2 で終わる。

### 引数

すべて `--arg k=v` の形で渡す。配列は JSON の文字列配列で渡す。

```bash
~/.agents/skills/multi-agent-development/scripts/mad-run research \
  --arg 'topic=対象' --arg 'perspectives=["現状","制約","代替案"]'
```

役割エージェントが読める範囲は `--cwd` に縛られる。`mad-run` はレシピを打った場所を
そのまま渡すので、**`--arg` で渡すパスは実行時の cwd の下にあること**。

例外は `implement` と `spike` のノードである。どちらも `--cwd` ではなく `--workspace` で
動くので、読める範囲は作った worktree になる。`--arg` で渡すパスは `mad-run` を打った
場所で読むので、この違いは引数の渡し方には影響しない。

レシピが受け取らない引数名を渡すと 2 で終わる。受け取る引数の一覧は、`mad-run` を
引数なしで呼ぶと出る。

```bash
~/.agents/skills/multi-agent-development/scripts/mad-run
```

同時に起こすエージェントの数は既定で 4 である。`--max-parallel <数>` で変えられる。
`fanout` に項目を多く渡すときだけ触る。

### 出力

成功すると最終ノードの構造化 JSON が標準出力に出る。ノードごとのプロンプト・出力・ログは
run ディレクトリ `_cellfusion/mad/<runId>/` に残る。

`implement` と `refine` は、レビューが `FAIL` のまま `max_rounds` に達しても 0 で終わる。
終了コードだけでは通ったかどうかが分からないので、呼び出し側が出力の `.status` を読む。

### 失敗したとき

**リトライしない。** 同じ条件の再試行は同じ結果になる。失敗したノードの名前と、run
ディレクトリのパスを報告する。片付けは利用者が行う。

### run を追う

```bash
paseo ls              # 走っているエージェントの一覧
paseo logs "$id"      # 1 つのエージェントの経過
paseo stop "$id"      # 停止
```

エージェントの title は `mad/<runId>/<ノード名>` になっている。

run ディレクトリと、実装レシピが作った worktree は自動では消えない。片付けは
`mad-runs clean --older-than <日数>` で対象を確かめてから、`--yes` を付けて実行する。

```bash
~/.agents/skills/multi-agent-development/scripts/mad-runs clean --older-than 7
```
