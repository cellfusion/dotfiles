'use strict'

const COMPLEXITIES = ['simple', 'routine', 'complex', 'critical']
const WORK_CLASSES = ['mechanical', 'routine', 'integration', 'architectural']
const WORK_CLASS_BY_COMPLEXITY = {
  simple: 'mechanical',
  routine: 'routine',
  complex: 'integration',
  critical: 'architectural',
}

function fenceMarker(line) {
  const match = /^\s*(`{3,}|~{3,})(.*)$/.exec(line)
  return match === null ? null : { character: match[1][0], length: match[1].length }
}

function closesFence(line, fence) {
  const match = /^\s*(`{3,}|~{3,})\s*$/.exec(line)
  return match !== null && match[1][0] === fence.character && match[1].length >= fence.length
}

function parsePlan(text) {
  if (typeof text !== 'string') throw new Error('plan は string でなければならない')
  const lines = text.split(/\r?\n/)
  const headings = []
  let fence = null
  for (let index = 0; index < lines.length; index += 1) {
    if (fence !== null) {
      if (closesFence(lines[index], fence)) fence = null
      continue
    }
    const marker = fenceMarker(lines[index])
    if (marker !== null) {
      fence = marker
      continue
    }
    const match = /^#{1,6}\s+Task\s+(\d+)\b/i.exec(lines[index])
    if (match !== null) headings.push({ index, number: Number(match[1]) })
  }
  if (headings.length === 0) throw new Error('Task 見出しがない')

  const tasks = new Map()
  const warnings = []
  for (let position = 0; position < headings.length; position += 1) {
    const heading = headings[position]
    if (tasks.has(heading.number)) throw new Error('Task 番号が重複する')
    const end = position + 1 < headings.length ? headings[position + 1].index : lines.length
    const block = lines.slice(heading.index + 1, end)
    const task = {
      number: heading.number,
      dependsOn: [],
      hasDependsOn: false,
      files: [],
      complexity: undefined,
      workClass: undefined,
    }

    let inFiles = false
    let blockFence = null
    for (const line of block) {
      if (blockFence !== null) {
        if (closesFence(line, blockFence)) blockFence = null
        continue
      }
      const marker = fenceMarker(line)
      if (marker !== null) {
        blockFence = marker
        inFiles = false
        continue
      }
      if (/\bDepends on\s*:/i.test(line)) {
        inFiles = false
        task.hasDependsOn = true
        const dependencyText = line.split(/\bDepends on\s*:/i)[1]
        const dependencies = [...dependencyText.matchAll(/\bTask\s+(\d+)\b/gi)]
        task.dependsOn.push(...dependencies.map((match) => Number(match[1])))
        continue
      }
      if (/\bComplexity\s*:/i.test(line)) {
        inFiles = false
        const match = /\bComplexity\s*:\s*\**\s*([A-Za-z]+)/i.exec(line)
        task.complexity = match === null ? '' : match[1].toLowerCase()
        continue
      }
      if (/\bWork class\s*:/i.test(line)) {
        inFiles = false
        const match = /\bWork class\s*:\s*\**\s*([A-Za-z]+)/i.exec(line)
        task.workClass = match === null ? '' : match[1].toLowerCase()
        continue
      }
      if (/\bFiles\s*:/i.test(line)) {
        inFiles = true
        const after = line.split(/\bFiles\s*:/i)[1]
        for (const match of after.matchAll(/`([^`]+)`/g)) task.files.push(match[1])
        continue
      }
      if (inFiles) {
        if (/^\s*[-*]\s+/.test(line)) {
          for (const match of line.matchAll(/`([^`]+)`/g)) task.files.push(match[1])
        } else if (/^\s*\*\*[^*]+\*\*/.test(line) || /^#{1,6}\s+/.test(line)) {
          inFiles = false
        }
      }
    }

    task.dependsOn = [...new Set(task.dependsOn)]
    task.files = [...new Set(task.files)]
    if (task.files.length === 0) throw new Error(`Task ${task.number}: Files がない`)
    if (task.complexity === undefined || task.complexity === '') task.complexity = 'routine'
    if (task.complexity === 'standard') {
      warnings.push(`Task ${task.number}: Complexity standard は routine へ読み替えた。simple/routine/complex/critical のいずれかに直すこと`)
      task.complexity = 'routine'
    } else if (!COMPLEXITIES.includes(task.complexity)) {
      throw new Error(`Task ${task.number}: Complexity が simple/routine/complex/critical でない`)
    }
    if (task.workClass === undefined || task.workClass === '') task.workClass = WORK_CLASS_BY_COMPLEXITY[task.complexity]
    if (!WORK_CLASSES.includes(task.workClass)) {
      throw new Error(`Task ${task.number}: Work class が mechanical/routine/integration/architectural でない`)
    }
    tasks.set(task.number, task)
  }

  const taskNumbers = [...tasks.keys()].sort((left, right) => left - right)
  for (const task of tasks.values()) {
    if (!task.hasDependsOn) task.dependsOn = taskNumbers.filter((number) => number < task.number)
  }
  return { tasks, warnings, hasAnyDependsOn: [...tasks.values()].some((task) => task.hasDependsOn) }
}

function validateDependencies(tasks) {
  for (const task of tasks.values()) {
    for (const dependency of task.dependsOn) {
      if (!tasks.has(dependency)) throw new Error(`Task ${task.number}: 未知の依存 Task`)
    }
  }

  const depth = new Map()
  const visiting = new Set()
  const visit = (number) => {
    if (depth.has(number)) return depth.get(number)
    if (visiting.has(number)) throw new Error('Task dependency に循環がある')
    visiting.add(number)
    const task = tasks.get(number)
    const value = task.dependsOn.length === 0
      ? 0
      : Math.max(...task.dependsOn.map((dependency) => visit(dependency) + 1))
    visiting.delete(number)
    depth.set(number, value)
    return value
  }
  for (const number of tasks.keys()) visit(number)

  const waves = new Map()
  const orderedTasks = [...tasks.values()].sort((left, right) => left.number - right.number)
  for (const task of orderedTasks) {
    const wave = depth.get(task.number)
    if (!waves.has(wave)) waves.set(wave, [])
    waves.get(wave).push(task)
  }
  for (const waveTasks of waves.values()) {
    for (let index = 0; index < waveTasks.length; index += 1) {
      for (let other = index + 1; other < waveTasks.length; other += 1) {
        const files = new Set(waveTasks[index].files)
        if (waveTasks[other].files.some((file) => files.has(file))) {
          throw new Error('同じ wave の Files が衝突する')
        }
      }
    }
  }
  return waves
}

function dependencyWaves(tasks) {
  return validateDependencies(tasks)
}

module.exports = {
  COMPLEXITIES,
  WORK_CLASSES,
  WORK_CLASS_BY_COMPLEXITY,
  parsePlan,
  validateDependencies,
  dependencyWaves,
}
