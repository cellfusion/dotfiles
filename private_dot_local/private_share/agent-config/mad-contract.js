'use strict'

class MadContractError extends Error {
  constructor(message, code = 'invalid_mad_record') {
    super(message)
    this.name = 'MadContractError'
    this.exitCode = 2
    this.code = code
  }
}

function fail(code, message) {
  throw new MadContractError(message, code)
}

function parseJsonWithoutDuplicateKeys(raw, code, label) {
  if (typeof raw !== 'string') fail(code, `${label}: JSON が不正である`)
  let index = 0
  const whitespace = () => { while (/\s/.test(raw[index] || '')) index += 1 }
  const invalid = () => { throw new Error('invalid JSON') }
  const parseString = () => {
    if (raw[index] !== '"') invalid()
    const start = index
    index += 1
    while (index < raw.length) {
      const character = raw[index]
      if (character === '"') {
        index += 1
        return JSON.parse(raw.slice(start, index))
      }
      if (character === '\\') {
        index += 1
        const escaped = raw[index]
        if (!'"\\/bfnrtu'.includes(escaped || '')) invalid()
        if (escaped === 'u') {
          const hex = raw.slice(index + 1, index + 5)
          if (!/^[0-9A-Fa-f]{4}$/.test(hex)) invalid()
          index += 4
        }
        index += 1
        continue
      }
      if (character < ' ') invalid()
      index += 1
    }
    invalid()
  }
  const parseValue = () => {
    whitespace()
    if (raw[index] === '{') {
      index += 1
      whitespace()
      // A null prototype makes every parsed JSON key an own data property.
      // In particular, `__proto__` must remain visible to exactKeys instead of
      // mutating this parser's object prototype.
      const object = Object.create(null)
      const keys = new Set()
      if (raw[index] === '}') { index += 1; return object }
      while (true) {
        whitespace()
        const key = parseString()
        if (keys.has(key)) invalid()
        keys.add(key)
        whitespace()
        if (raw[index] !== ':') invalid()
        index += 1
        object[key] = parseValue()
        whitespace()
        if (raw[index] === '}') { index += 1; return object }
        if (raw[index] !== ',') invalid()
        index += 1
      }
    }
    if (raw[index] === '[') {
      index += 1
      whitespace()
      const array = []
      if (raw[index] === ']') { index += 1; return array }
      while (true) {
        array.push(parseValue())
        whitespace()
        if (raw[index] === ']') { index += 1; return array }
        if (raw[index] !== ',') invalid()
        index += 1
      }
    }
    if (raw[index] === '"') return parseString()
    for (const [literal, parsed] of [['true', true], ['false', false], ['null', null]]) {
      if (raw.startsWith(literal, index)) { index += literal.length; return parsed }
    }
    const match = raw.slice(index).match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/)
    if (!match) invalid()
    index += match[0].length
    return Number(match[0])
  }
  try {
    const value = parseValue()
    whitespace()
    if (index !== raw.length) invalid()
    return value
  } catch {
    fail(code, `${label}: JSON が不正である`)
  }
}

module.exports = { MadContractError, parseJsonWithoutDuplicateKeys }
