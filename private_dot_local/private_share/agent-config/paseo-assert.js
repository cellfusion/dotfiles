'use strict'

const { ConfigError } = require('./config-validator.js')
const { DUTIES, COMPLEXITIES } = require('./config-types.js')

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function exactKeys(value, keys, label) {
  const actual = isObject(value) ? Object.keys(value).sort() : []
  const expected = [...keys].sort()
  if (!isObject(value) || actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new ConfigError(`${label}: key set が不正である`)
  }
}

function nonEmptyString(value, label) {
  if (typeof value !== 'string' || value.length === 0) throw new ConfigError(`${label}: 非空 string が必要である`)
}

function assertUniqueStrings(values, label) {
  if (!Array.isArray(values) || !values.every((value) => typeof value === 'string')) {
    throw new ConfigError(`${label}: string 配列が必要である`)
  }
  if (new Set(values).size !== values.length) throw new ConfigError(`${label}: 重複がある`)
}

function assertCandidateResolution(resolution) {
  if (!isObject(resolution)) throw new ConfigError('resolved config: resolution が不正である')
  if (!DUTIES.includes(resolution.duty) || !COMPLEXITIES.includes(resolution.complexity) ||
      typeof resolution.environment !== 'string') {
    throw new ConfigError('resolved config: resolution の discriminator が不正である')
  }
  if (!Array.isArray(resolution.candidates) || resolution.candidates.length === 0) {
    throw new ConfigError('resolved config: resolution の candidate がない')
  }
}

module.exports = { isObject, exactKeys, nonEmptyString, assertUniqueStrings, assertCandidateResolution }
