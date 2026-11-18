'use strict';

function select(options, env = process.env) {
  const hosts = [];
  if (env.HERDR_ENV === '1') hosts.push('herdr');
  if (env.HC_TERMINAL_ID) hosts.push('herdr-core');
  if (env.ORCA_TERMINAL_HANDLE || env.ORCA_WORKTREE_ID || env.ORCA_DEV_REPO_ROOT) hosts.push('orca');
  const name = options.environment || (hosts.length === 1 ? hosts[0] : null);
  if (!name) throw new Error(hosts.length > 1 ? 'ambiguous-host: use --environment herdr|herdr-core|orca|paseo' : 'unknown-host: use --environment herdr|herdr-core|orca|paseo');
  if (name === 'paseo') throw new Error('unsupported-environment: Paseo CLI capabilities are not verified; no resources created');
  if (name === 'herdr' && env.HERDR_ENV !== '1') throw new Error('herdr-outside: run inside Herdr (HERDR_ENV=1)');
  if (options.project && name !== 'orca') throw new Error('--project is Orca-only; use --repo-path for Herdr or herdr-core');
  if (options.repoPath && !['herdr', 'herdr-core'].includes(name)) throw new Error('--repo-path is Herdr/herdr-core-only; use --project for Orca');
  return name;
}
function load(name) {
  if (name === 'herdr') return require('./herdr.js');
  if (name === 'herdr-core') return require('./herdr-core.js');
  if (name === 'orca') return require('./orca.js');
  throw new Error('unsupported-environment');
}
module.exports = { select, load };
