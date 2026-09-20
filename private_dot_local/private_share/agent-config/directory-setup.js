'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { ConfigError } = require('./config-validator.js')

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function fail(message) {
  throw new ConfigError(message)
}

function requireAbsoluteDirectory(value, label) {
  if (typeof value !== 'string' || value.length === 0 || !path.isAbsolute(value)) {
    fail(`${label}: 絶対 path が必要である`)
  }
  return path.normalize(value)
}

function requireEnvironmentName(value, label) {
  if (typeof value !== 'string' || !/^[a-z][a-z0-9_-]*$/.test(value)) {
    fail(`${label}: environment が不正である`)
  }
  return value
}

function readEntry(pathname, label) {
  try {
    return fs.lstatSync(pathname)
  } catch (error) {
    if (error && (error.code === 'ENOENT' || error.code === 'ENOTDIR')) return null
    fail(`${label}: entry を検査できない`)
  }
}

function ensurePrimaryEntry(pathname, label) {
  const entry = readEntry(pathname, label)
  if (!entry) fail(`${label}: primary に存在しない`)
  if (entry.isSymbolicLink()) fail(`${label}: symlink は許可しない`)
  if (!entry.isFile() && !entry.isDirectory()) {
    fail(`${label}: regular file 又は directory が必要である`)
  }
  return entry
}

function expandDirectoryPattern(pattern, xdgConfigHome, environment, label) {
  if (typeof pattern !== 'string' || pattern.length === 0) fail(`${label}: directory pattern が不正である`)
  const home = process.env.HOME
  if (typeof home !== 'string' || !path.isAbsolute(home)) fail(`${label}: HOME が絶対 path でない`)
  const expanded = pattern
    .replaceAll('$XDG_CONFIG_HOME', () => xdgConfigHome)
    .replaceAll('$HOME', () => home)
    .replaceAll('<environment>', () => environment)
  if (!path.isAbsolute(expanded)) fail(`${label}: directory pattern が絶対 path でない`)
  const normalized = path.normalize(expanded)
  const roots = [path.resolve(xdgConfigHome), path.resolve(home)]
  const insideRoot = roots.some((root) => {
    const relative = path.relative(root, normalized)
    return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative)
  })
  if (!insideRoot) fail(`${label}: directory pattern が許可された root の外側である`)
  return normalized
}

function validateSetupPaths(setup, family) {
  if (!isObject(setup) || !Array.isArray(setup.symlinks)) fail(`provider family ${family}: setup が不正である`)
  for (const [index, entry] of setup.symlinks.entries()) {
    if (typeof entry !== 'string' || entry.length === 0 || path.posix.isAbsolute(entry) || entry.split('/').includes('..')) {
      fail(`provider family ${family}: symlinks[${index}] の path が不正である`)
    }
  }
}

function validateRoot(pathname, label) {
  const entry = readEntry(pathname, label)
  if (!entry) return false
  if (entry.isSymbolicLink()) fail(`${label}: symlink を置き換えない`)
  if (!entry.isDirectory()) fail(`${label}: directory でない`)
  return true
}

function addParentDirectories(root, parent, directories, label) {
  const rootPath = path.resolve(root)
  const parentPath = path.resolve(parent)
  const relative = path.relative(rootPath, parentPath)
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    fail(`${label}: destination が root の外側である`)
  }

  const missing = []
  let current = parentPath
  while (current !== rootPath) {
    const entry = readEntry(current, label)
    if (entry) {
      if (entry.isSymbolicLink() || !entry.isDirectory()) fail(`${label}: parent directory が不正である`)
      break
    }
    missing.push(current)
    current = path.dirname(current)
  }
  for (const directory of missing.reverse()) directories.add(directory)
}

function planSetup(config, options) {
  if (!isObject(config) || !isObject(config.providers) || !isObject(config.environments)) {
    fail('agent config: shape が不正である')
  }
  if (!isObject(options)) fail('directory setup options: object が必要である')
  const xdgConfigHome = requireAbsoluteDirectory(options.xdgConfigHome, 'xdgConfigHome')
  const defaultEnvironment = requireEnvironmentName(options.defaultEnvironment, 'defaultEnvironment')
  if (!Object.prototype.hasOwnProperty.call(config.environments, defaultEnvironment)) {
    fail(`defaultEnvironment ${defaultEnvironment}: 正本にない`)
  }

  const directories = new Set()
  const links = []
  for (const [family, definition] of Object.entries(config.providers)) {
    if (!isObject(definition) || definition.setup === null) continue
    const setup = definition.setup
    validateSetupPaths(setup, family)
    for (const [environment, environmentConfig] of Object.entries(config.environments)) {
      if (environment === defaultEnvironment) continue
      if (!isObject(environmentConfig) || !Array.isArray(environmentConfig.providers) ||
          !environmentConfig.providers.includes(family)) continue

      const primary = expandDirectoryPattern(
        setup.directoryPattern && setup.directoryPattern.primary,
        xdgConfigHome,
        defaultEnvironment,
        `provider family ${family}: primary`,
      )
      const root = expandDirectoryPattern(
        setup.directoryPattern && setup.directoryPattern.nonPrimary,
        xdgConfigHome,
        environment,
        `provider family ${family}/${environment}: nonPrimary`,
      )
      if (!validateRoot(root, `provider family ${family}/${environment}: root`)) directories.add(root)

      for (const relative of setup.symlinks) {
        const source = path.resolve(primary, relative)
        const sourceRelative = path.relative(primary, source)
        if (sourceRelative === '..' || sourceRelative.startsWith(`..${path.sep}`) || path.isAbsolute(sourceRelative)) {
          fail(`provider family ${family}/${environment}: source が primary の外側である`)
        }
        ensurePrimaryEntry(source, `provider family ${family}: symlink source ${relative}`)
        const destination = path.resolve(root, relative)
        const destinationRelative = path.relative(root, destination)
        if (destinationRelative === '..' || destinationRelative.startsWith(`..${path.sep}`) || path.isAbsolute(destinationRelative)) {
          fail(`provider family ${family}/${environment}: destination が root の外側である`)
        }
        addParentDirectories(root, path.dirname(destination), directories, `provider family ${family}/${environment}: ${relative}`)
        const target = path.relative(path.dirname(destination), source)
        if (target.length === 0 || path.isAbsolute(target)) fail(`provider family ${family}/${environment}: relative target が不正である`)
        const existing = readEntry(destination, `provider family ${family}/${environment}: ${relative}`)
        if (!existing) {
          links.push({ destination, target, family, environment, relative })
        } else if (existing.isSymbolicLink()) {
          let actualTarget
          try {
            actualTarget = fs.readlinkSync(destination)
          } catch {
            fail(`provider family ${family}/${environment}: ${relative} の symlink を読めない`)
          }
          if (actualTarget !== target) {
            fail(`provider family ${family}/${environment}: ${relative} の symlink が違う`)
          }
        } else {
          fail(`provider family ${family}/${environment}: ${relative} の実体を置き換えない`)
        }
      }
    }
  }
  return { directories, links }
}

function createDirectory(pathname, label) {
  let created = false
  try {
    fs.mkdirSync(pathname, { mode: 0o700 })
    created = true
  } catch (error) {
    if (!error || error.code !== 'EEXIST') fail(`${label}: directory を作れない`)
  }
  const entry = readEntry(pathname, label)
  if (!entry || entry.isSymbolicLink() || !entry.isDirectory()) fail(`${label}: directory が不正である`)
  if (created) {
    try {
      fs.chmodSync(pathname, 0o700)
    } catch {
      fail(`${label}: mode を設定できない`)
    }
  }
}

function createRelativeLink(link) {
  try {
    fs.symlinkSync(link.target, link.destination)
  } catch (error) {
    if (!error || error.code !== 'EEXIST') {
      fail(`provider family ${link.family}/${link.environment}: ${link.relative} の symlink を作れない`)
    }
    const entry = readEntry(link.destination, `provider family ${link.family}/${link.environment}: ${link.relative}`)
    if (!entry || !entry.isSymbolicLink()) {
      fail(`provider family ${link.family}/${link.environment}: ${link.relative} の実体を置き換えない`)
    }
    let actualTarget
    try {
      actualTarget = fs.readlinkSync(link.destination)
    } catch {
      fail(`provider family ${link.family}/${link.environment}: ${link.relative} の symlink を読めない`)
    }
    if (actualTarget !== link.target) fail(`provider family ${link.family}/${link.environment}: ${link.relative} の symlink が違う`)
  }
}

function setupDirectories(config, options) {
  const plan = planSetup(config, options)
  const directories = [...plan.directories].sort((left, right) => left.length - right.length)
  for (const directory of directories) createDirectory(directory, 'non-primary root')
  for (const link of plan.links) createRelativeLink(link)
}

module.exports = { setupDirectories, expandDirectoryPattern }
