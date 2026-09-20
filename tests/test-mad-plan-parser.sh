#!/usr/bin/env bash
# MAD plan の parser と dependency graph を共有実装で検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
parser="$root/private_dot_agents/skills/multi-agent-development/scripts/mad-plan-parser.js"

if node - "$parser" <<'NODE'
const parser = require(process.argv[2])
const plan = parser.parsePlan(`
### Task 2: second

**Files:**
- Modify: \`two.txt\`

**Depends on:** Task 1

### Task 1: first

**Files:**
- Create: \`one.txt\`

**Depends on:** none
`)

const first = plan.tasks.get(1)
const second = plan.tasks.get(2)
if (!first || !second) throw new Error('tasks were not parsed')
if (first.complexity !== 'routine' || first.workClass !== 'routine') throw new Error('default task metadata is wrong')
if (second.dependsOn.length !== 1 || second.dependsOn[0] !== 1) throw new Error('dependencies were not parsed')
if (JSON.stringify(first.files) !== JSON.stringify(['one.txt'])) throw new Error('files were not parsed')
const waves = [...parser.dependencyWaves(plan.tasks)].map(([wave, tasks]) => [wave, tasks.map((task) => task.number)])
if (JSON.stringify(waves) !== JSON.stringify([[0, [1]], [1, [2]]])) throw new Error(`waves are wrong: ${JSON.stringify(waves)}`)

const fallback = parser.parsePlan(`
### Task 1: fixture

**Files:**
- Modify: \`fixture.txt\`

**Depends on:** none

**Complexity:** standard
`)
if (fallback.warnings.length !== 1 || !fallback.warnings[0].includes('routine')) throw new Error('standard warning is missing')
if (fallback.tasks.get(1).complexity !== 'routine') throw new Error('standard was not normalized')
NODE
then
  pass 'plan parser は metadata、依存、wave、warning を一元的に解釈する'
else
  fail_check 'plan parser は metadata、依存、wave、warning を一元的に解釈する'
fi

assert_summary
