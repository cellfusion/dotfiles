---
name: rive
description: >-
  Guidance for animation editing, data binding, and Rive Scripting via the Rive CLI (RML).
  Activates automatically when the user mentions keywords like "Rive", ".riv", ".rev", "RML",
  "artboard", "state machine", "data bind", "Luau", "rive CLI", etc.
  Can also be invoked manually with /rive.
---

# Rive CLI Development Skill

Procedures and pitfalls when editing `.riv` and `.rev` with the `rive` CLI.
Applies to writing RML (text) and building with the CLI rather than GUI operations in the Rive editor.

## What to Read First

RML and the Rive CLI are newer than standard pretraining cuts. **Never write type names or property names from memory.**

```bash
rive schema <Type>              # Inspect properties and propertyKey of a type
rive schema --search <text>     # Search for type names
rive docs --list                # List topics
rive docs <topic>               # Read specific topic
```

In environments where `rive docs --list` returns different content, read local docs directly:

```
$HOME/.rive/versions/<version>/docs/
  format.md              RML structure, IDs, and references
  data.md                Data binding, converters, stateful nested artboards
  state-machines.md      Transitions and conditions
  publishing.md          Signing and --publish
  luau/protocols.md      Script protocols
  luau/api/*.md          Luau APIs
  project/rive-yaml.md   rive.yaml
```

Samples are also available. `rive samples --path` shows their location. `rml_vm_input` and `rml_split` are minimal examples of data binding and file splitting.

## Common Pitfalls

All 4 of these pass `--verify`. You cannot detect them without manual verification.

### 1. Build `.riv` Containing Scripts with `--publish`

`--once` writes an **unsigned** `.riv`. Flutter and web runtimes reject unsigned scripts and throw `ScriptAsset doesn't have a generator function <name>`. The CLI viewer runs unsigned scripts, so it appears to work locally.

```bash
rive . --publish --rev=build/<name>.rev   # Requires rive login
```

`--publish` sends the script to Rive's compile service to write bytecodes and signatures. If it outputs `signed N scripts`, it succeeded. Check for watermarks before releasing to production.

### 2. ViewModels Passed via Luau `instance(vm)` Do Not Reach Bindings

A ViewModel passed to `artboard:instance(vm)` is not reflected in the generated artboard's data bindings. Values are set correctly in Luau, but the visual display retains default values. Neither `sourcePathIds`, `viewModelInstanceId`, `advance(0)` immediately after `instance()`, nor passing a new VM with copied values work.

Conversely, `dataBindPathIds` on `NestedArtboard` works properly.

**Pass values via RML bindings; drive animations via timelines or Luau.** Dynamic artboard instantiations distributing values in Luau cannot be used. Place a fixed number of properties in the ViewModel and define `NestedArtboard` statically:

```xml
<!-- Works: Each placement receives a distinct ViewModel instance -->
<NestedArtboard artboardId="0:100" dataBindPathIds="0:14-0:201" name="Card1" id="0:300"/>
<NestedArtboard artboardId="0:100" dataBindPathIds="0:14-0:202" name="Card2" id="0:310"/>
```

### 3. Binding Numbers to Text Requires `DataConverterToString`

When binding numbers to `TextValueRun` (propertyKey 268), interpolate a converter via `converterId`. Without it, types mismatch and default text appears.

```xml
<DataConverterToString round="true" name="Number To Text" id="0:900"/>
<DataBindContext sourcePathIds="0:100-0:101" propertyKey="268" converterId="0:900" id="0:901"/>
```

See the Converters section in `data.md` for a full list (`DataConverterRangeMapper`, `DataConverterEnumToUint`, `DataConverterListToLength`, etc.).

### 4. When Renumbering IDs, Update the Referencing Side

Replacing only the declaration (`id="0:..."`) leaves referencing sites pointing to non-existent IDs. `--verify` permits this (a non-existent `scriptAssetId` is treated as a `ScriptedDrawable` without scripts).

Referencing attributes: `scriptAssetId`, `objectId`, `animationId`, `stateToId`, `defaultStateMachineId`, `artboardId`, `styleId`, `dataBindPathIds`, `sourcePathIds`, `viewModelPropertyId`, `viewModelInstanceId`, `enumId`, `converterId`, `assetId`.

IDs are `client:object` numerical pairs and must be unique across all files. Reserve contiguous ranges before numbering.

## Post-Edit Verification

"A clean verify/inspect is not enough" from `AGENTS.md` applies literally here:

```bash
rive . --verify                              # Compiles only. Does not execute
rive inspect . --json                        # Assembled structure
rive . --artboard=<name> --screenshot=<path> --viewport=<W>x<H> --advance=<N>s
```

- `--verify` only type-checks. It does not invoke scripts, so runtime bugs remain hidden.
- Even if asset files are missing, `--verify` and `.riv` pass; failure occurs only when writing `--rev`.
- **Always capture and inspect visual images for visual changes.** Take screenshots across different timestamps to verify transitions.
- Pass ViewModel values via `--data=<path>=<value>`. Does not work on component artboards (`isComponent="true"`), resulting in `no view model is bound to this artboard`.

`--advance` fast-forwards time in bulk, so multiple events may appear on a single frame. Take multiple captures at different timestamps to verify intervals.

## RML Conventions

- **Elements written earlier are rendered in front.** Write backgrounds last.
- When an artboard's `originX`/`originY` is 0.5, the origin is centered.
- Rounded corners on `Rectangle` use `cornerRadiusTL` (affects all 4 corners if `linkCornerRadius` is true).
- Center text alignment uses `alignValue="2"`. `accepts` order is left / right / **center** (1 is right).
- `Solo` maps enum values by child **name**. `activeComponentId` is of type Id (propertyKey 296).
- Keyframing `NestedRemapAnimation.time` (propertyKey 202, seconds) on the parent timeline allows parent timelines to drive nested artboard animations. You cannot directly keyframe elements inside nested artboards from the parent; create a timeline on the child and send time.
- To run a state machine inside a nested artboard, place a `NestedStateMachine`. When used with `NestedRemapAnimation`, remap takes precedence.
- Frequent propertyKeys: 13=x, 14=y, 15=rotation, 16=scaleX, 17=scaleY, 18=opacity, 202=nested time, 245=ScriptInputBoolean.propertyValue, 268=TextValueRun.text, 296=Solo.activeComponentId, 636=number bind, 637=enum bind, 686=trigger bind, 869=ScriptInputTrigger.fire (`KeyFrameCallback`), 870=ScriptInputTrigger.propertyValue.

### File Organization

A project can place any number of `.rml` files in any directory. They compile into a single document, and IDs can be referenced across files without explicit includes.

Keeping 1 artboard per file, with ViewModels/enums under `data/` and asset declarations in `assets.rml`, provides clean organization. Specifying `main` in `rive.yaml` eliminates dependency on compilation order.

`rive create --from-rev` preserves this separation. Elements added in the editor go into `scene.rml`, making it easy to sort them according to conventions.

### State Machine Transition Order

Transitions evaluate in RML definition order, taking the first match. **Placing an unconditional transition first blocks subsequent conditional transitions.** Order from most specific to least specific.

## Rive Scripting (Luau)

- Protocols: Node / Layout / PathEffect / Converter / Listener / Transition / Tests.
- Hooks for `Node<T>`: `init(self, context)`, `advance(self, seconds)`, `update(self)`, `draw(self, renderer)`. All are optional; **typos result in silent omission without calls**.
- Type checking is strict; type errors cause build failures. Always type function parameters.
- Data context is not established during `init`. Retain `context` and call `context:viewModel()` or `context:rootViewModel()` when needed.
- `Input<Trigger>` fields are functions invoked when fired. Can be fired via timeline `KeyFrameCallback` (propertyKey 869).
- `print` outputs to CLI build logs and consoles; does not print in Flutter.
- Available libraries: `math`, `table`, `string`, `os`, `utf8`, `buffer`, `bit32`, and base library. `io`, `coroutine`, `debug` are unavailable.

## When Using from Flutter

- In stable `rive`, construct `RiveWidgetController(file, artboardSelector:, stateMachineSelector:)` and fetch ViewModels with `controller.dataBind(rive.DataBind.auto())`. Dev releases (0.15.0-dev+) bind automatically during construction and retrieve via `controller.viewModelInstance`.
- Retrieving ViewModel properties allocates native objects on each invocation. Resolve and cache once immediately after binding, releasing in `dispose`.
- Nested ViewModels are retrieved by path: `vm.viewModel('name')`.
- Mismatches between artboard and state machine names throw exceptions. Verify actual names with `rive inspect`.
- Verification is fastest in a minimal `flutter create` project with only `rive` added rather than the full application.
