---
name: rive
description: >-
  Rive CLI（RML）でのアニメーション編集・データバインド・Rive Scripting のガイダンス。
  ユーザーが「Rive」「.riv」「.rev」「RML」「artboard」「アートボード」
  「state machine」「ステートマシン」「data bind」「データバインド」
  「Luau」「rive CLI」などのキーワードを使った際に自動起動。
  /rive で手動起動も可能。
---

# Rive CLI 開発スキル

`rive` CLI で `.riv` と `.rev` を編集するときの手順と落とし穴をまとめる。
Rive エディタでの GUI 操作ではなく、RML（テキスト）を書いて CLI でビルドする作業を対象にする。

## まず読むもの

RML と Rive CLI は訓練データより新しい。**型名とプロパティ名を記憶で書かない。**

```bash
rive schema <Type>              # 型のプロパティと propertyKey
rive schema --search <text>     # 型名を探す
rive docs --list                # トピック一覧
rive docs <topic>               # 該当トピック
```

`rive docs --list` が別の内容を返す環境では、ローカルのドキュメントを直接読む。

```
$HOME/.rive/versions/<version>/docs/
  format.md              RML の構造、id と参照
  data.md                データバインド、コンバータ、stateful nested artboard
  state-machines.md      遷移と条件
  publishing.md          署名と --publish
  luau/protocols.md      スクリプトの protocol
  luau/api/*.md          Luau の API
  project/rive-yaml.md   rive.yaml
```

サンプルも読める。`rive samples --path` が置き場所を返す。`rml_vm_input` と `rml_split` が
データバインドとファイル分割の最小例である。

## 落とし穴

この 4 つは `--verify` を通過する。自分で確認しないと気づけない。

### 1. スクリプトを含む `.riv` は `--publish` でビルドする

`--once` が書くのは**未署名**の `.riv` で、Flutter と web のランタイムはスクリプトを拒否し
`ScriptAsset doesn't have a generator function <name>` を出す。CLI 自身のビューアは未署名でも
動かすため、手元では動いて見える。

```bash
rive . --publish --rev=build/<name>.rev   # rive login が必要
```

`--publish` はスクリプトを Rive の compile service へ送り、バイトコードと署名を書き込む。
`signed N scripts` と出れば通っている。`watermarked` と出る条件は未確認なので、本番に出す前に
透かしの有無を確認する。

### 2. Luau の `instance(vm)` で渡した ViewModel はバインドに届かない

`artboard:instance(vm)` に渡した ViewModel は、生成された artboard のデータバインドに反映
されない。値は Luau 側では正しく入るのに、表示は既定値のままになる。`sourcePathIds` の書き方、
`viewModelInstanceId` の有無、`instance()` 直後の `advance(0)`、値を写した新しい VM を渡す、の
いずれも効かない（最小構成で確認済み）。

一方 `NestedArtboard` の `dataBindPathIds` は効く。

**値は RML のバインドで渡し、動きはタイムラインか Luau で打つ。** Luau で artboard を動的に
生成して値を配る設計は採れない。固定数のプロパティを ViewModel に並べ、`NestedArtboard` を
静的に置く。

```xml
<!-- 効く。placement ごとに別の ViewModel インスタンスを受ける -->
<NestedArtboard artboardId="0:100" dataBindPathIds="0:14-0:201" name="Card1" id="0:300"/>
<NestedArtboard artboardId="0:100" dataBindPathIds="0:14-0:202" name="Card2" id="0:310"/>
```

### 3. 数値をテキストに出すには `DataConverterToString` が要る

`TextValueRun`（propertyKey 268）に number をバインドするときは `converterId` で変換器を挟む。
無いと型が合わず、`text` 属性の既定の文字がそのまま出る。

```xml
<DataConverterToString round="true" name="Number To Text" id="0:900"/>
<DataBindContext sourcePathIds="0:100-0:101" propertyKey="268" converterId="0:900" id="0:901"/>
```

コンバータの一覧は `data.md` の Converters 節にある。`DataConverterRangeMapper`（number→number）、
`DataConverterEnumToUint`、`DataConverterListToLength` など。

### 4. id を振り直すときは参照側も直す

宣言側（`id="0:..."`）だけ置換して参照側を直し忘れると、参照先が無い状態になる。`--verify` は
これを通す（存在しない `scriptAssetId` は「スクリプトの無い `ScriptedDrawable`」として扱われる）。

参照側の属性: `scriptAssetId` / `objectId` / `animationId` / `stateToId` /
`defaultStateMachineId` / `artboardId` / `styleId` / `dataBindPathIds` / `sourcePathIds` /
`viewModelPropertyId` / `viewModelInstanceId` / `enumId` / `converterId` / `assetId`

id は `client:object` の数値対で、ファイルを跨いで重複できない。まとまった空き範囲を確保して
から振る。

## 編集後の確認

`AGENTS.md` の「A clean verify/inspect is not enough」はそのままの意味である。

```bash
rive . --verify                              # コンパイルだけ。実行はしない
rive inspect . --json                        # 組み上がった構造
rive . --artboard=<name> --screenshot=<path> --viewport=<W>x<H> --advance=<N>s
```

- `--verify` は型チェックのみ。スクリプトを呼ばないので、実行時にしか出ない誤りは見えない
- アセットの実ファイルが欠けていても `--verify` と `.riv` は通る。`--rev` の書き出しで初めて失敗する
- **見た目が関わる変更は必ず画像を出して読む。** 時刻を変えて複数枚撮り、意図した順で
  変化しているかを確かめる
- `--data=<path>=<value>` で ViewModel の値を渡せる。ただし component artboard
  （`isComponent="true"`）には効かず `no view model is bound to this artboard` になる

`--advance` は一括で時間を進めるため、1 フレームに複数のイベントが重なって見えることがある。
間隔を確かめたいときは時刻を変えて複数回撮る。

## RML の作法

- **先に書いた要素が手前に描かれる。** 背景は最後に書く
- artboard の `originX`/`originY` が 0.5 だと座標系の原点が中心になる
- `Rectangle` の角丸は `cornerRadiusTL`（`linkCornerRadius` が true なら 4 隅に効く）
- `Text` の中央揃えは `alignValue="2"`。`accepts` は left / right / **center** の順で、1 は right
- `Solo` は子の**名前**で enum の値に対応づく。`activeComponentId` は Id 型（propertyKey 296）
- `NestedRemapAnimation.time`（propertyKey 202、秒）を親のタイムラインでキーフレームすると、
  子の artboard のアニメーションを親から駆動できる。nested artboard の中の要素を親から直接
  キーフレームすることはできないので、子側にタイムラインを作って time を送る
- nested artboard の中の state machine を動かすには `NestedStateMachine` を置く。
  `NestedRemapAnimation` と併用すると remap 側が優先される
- よく使う propertyKey: 13=x, 14=y, 15=rotation, 16=scaleX, 17=scaleY, 18=opacity,
  202=nested time, 245=ScriptInputBoolean.propertyValue, 268=TextValueRun.text,
  296=Solo.activeComponentId, 636=number の bind, 637=enum の bind, 686=trigger の bind,
  869=ScriptInputTrigger.fire（`KeyFrameCallback`）, 870=ScriptInputTrigger.propertyValue

### ファイル分割

プロジェクトは任意の数の `.rml` を任意のフォルダに置ける。1 つのドキュメントとしてコンパイル
され、id はファイルを跨いで参照できる。include の記述は要らない。

artboard 1 つを 1 ファイルにし、ViewModel と enum を `data/`、アセット参照を `assets.rml` に
分けると扱いやすい。`rive.yaml` の `main` で既定 artboard を決めておけば、ファイルの
コンパイル順（path 順）に依存しない。

`rive create --from-rev` はこの分割を保つ。エディタで追加された要素だけが `scene.rml` に入るので、
同じ規則で振り分ければ構成を維持できる。

### state machine の遷移順

遷移は RML に書いた順で評価され、最初に条件を満たしたものが選ばれる。**条件の無い遷移を
先に置くと、後ろの条件付き遷移には到達しない。** 条件の狭いものから並べる。

## Rive Scripting（Luau）

- protocol は Node / Layout / PathEffect / Converter / Listener / Transition / Tests
- `Node<T>` の hook は `init(self, context)` / `advance(self, seconds)` / `update(self)` /
  `draw(self, renderer)`。すべて optional で、**綴りを間違えると黙って呼ばれない**
- 型チェックは strict で、型エラーはビルドエラーになる。関数の引数には必ず型を書く
- data context は `init` の時点では立っていない。`context` を保持して、必要になってから
  `context:viewModel()` か `context:rootViewModel()` で引く
- `Input<Trigger>` はフィールドが関数で、fire されると呼ばれる。タイムラインの
  `KeyFrameCallback`（propertyKey 869）から発火できる
- `print` は CLI のビルドログとコンソールに出る。Flutter では出ない
- 使えるのは `math` / `table` / `string` / `os` / `utf8` / `buffer` / `bit32` と base library。
  `io` / `coroutine` / `debug` は無い

## Flutter から使うとき

- `rive` パッケージの安定版では `RiveWidgetController(file, artboardSelector:,
  stateMachineSelector:)` を作り、`controller.dataBind(rive.DataBind.auto())` で ViewModel を得る。
  dev 版（0.15.0-dev 以降）は構築時に自動でバインドし、`controller.viewModelInstance` で取る
- ViewModel のプロパティ取得は呼ぶたびにネイティブオブジェクトを確保する。バインド直後に
  1 回だけ解決して保持し、`dispose` で解放する
- 入れ子の ViewModel は `vm.viewModel('name')` でパス指定で取れる
- artboard 名と state machine 名の不一致は例外になる。`rive inspect` で実際の名前を確認する
- 動作確認は本体アプリではなく、`flutter create` した最小のプロジェクトに `rive` だけ足して
  `.riv` を読む形が速い。本体は依存が多くビルドが重い
