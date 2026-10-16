'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
function binary(env = process.env, platform = process.platform) {
  return env.ORCA_CLI_COMMAND || (env.ORCA_DEV_REPO_ROOT ? 'orca-dev' : platform === 'linux' && !env.ORCA_TERMINAL_HANDLE ? 'orca-ide' : 'orca');
}
function result(api, args, cwd, env = process.env) {
  const response = api.jsonCommand(binary(env), [...args, '--json'], cwd, env);
  if (response.ok !== true || !response.result) throw new Error('Orca request failed');
  return response.result;
}
function preflight(api) { api.command('/usr/bin/env', ['which', binary()]); }
function resolveRepository(api, options, resources) {
  const registrations = result(api, ['repo', 'list'], process.cwd()).repos.filter(repo => repo.kind === 'git' && typeof repo.path === 'string' && path.isAbsolute(repo.path));
  let matches;
  if (options.project) matches = registrations.filter(repo => options.project.startsWith('id:') ? repo.id === options.project.slice(3) : repo.displayName === options.project);
  else if (options.repository) matches = registrations.filter(repo => {
    try { return api.sameRepository(api.command('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], repo.path), options.repository); } catch { return false; }
  });
  else {
    const common = fs.realpathSync(api.git(process.cwd(), 'rev-parse', '--path-format=absolute', '--git-common-dir'));
    matches = registrations.filter(repo => { try { return fs.realpathSync(api.git(repo.path, 'rev-parse', '--path-format=absolute', '--git-common-dir')) === common; } catch { return false; } });
  }
  if (matches.length !== 1) { resources.projectResolutionError = matches.length ? 'ambiguous' : 'missing'; throw new Error('one matching registered Orca project required'); }
  resources.repoId = matches[0].id;
  return fs.realpathSync(api.git(matches[0].path, 'rev-parse', '--show-toplevel'));
}
function createCheckout(api, options, resources, fixed, cwd, persist) {
  const response = spawnSync(binary(), ['worktree', 'create', '--repo', `id:${resources.repoId}`, '--name', resources.name, '--base-branch', fixed.baseSha, '--no-parent', '--setup', 'skip', '--pr', String(options.number), ...(options.noFocus ? [] : ['--activate']), '--json'], { cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  Object.assign(resources.checkout, { owner: 'orca', path: data?.result?.worktree?.path || null, ownerId: data?.result?.worktree?.id || null, branch: data?.result?.worktree?.branch || null });
  persist();
  if (response.error || response.status !== 0 || data?.ok !== true) throw new Error('Orca worktree creation failed');
  if (!resources.checkout.path || !path.isAbsolute(resources.checkout.path) || resources.checkout.ownerId !== `${resources.repoId}::${resources.checkout.path}`) throw new Error('incomplete Orca worktree identity');
}
function startReviewer(api, resources, run, cwd, persist) {
  const argv = ['env', '-u', 'OMP_PROFILE', '-u', 'PI_CODING_AGENT_DIR', '-u', 'OMPCODE', 'omp', '--cwd', resources.checkout.path, '--session-dir', path.join(run, 'sessions'), '--config', path.join(run, 'omp-config.yml')];
  const response = spawnSync(binary(), ['terminal', 'create', '--worktree', `id:${resources.checkout.ownerId}`, '--title', resources.name, '--command', `umask 077; exec ${argv.map(api.shellQuote).join(' ')}`, '--json'], { cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  resources.interaction.terminalHandle = data?.result?.terminal?.handle || null; persist();
  if (response.error || response.status !== 0 || data?.ok !== true || !resources.interaction.terminalHandle) throw new Error('Orca terminal creation failed');
}
function ready(api, c, cwd) {
  let response = result(api, ['terminal', 'wait', '--terminal', c.interaction.terminalHandle, '--for', 'tui-idle', '--timeout-ms', '60000'], cwd);
  if (response.wait?.satisfied !== true) response = result(api, ['terminal', 'wait', '--terminal', c.interaction.terminalHandle, '--for', 'tui-idle', '--timeout-ms', '120000'], cwd);
  if (response.wait?.satisfied !== true) throw new Error('OMP terminal not ready');
}
function inspectIdentity(api, c, cwd, env) { return result(api, ['terminal', 'show', '--terminal', c.interaction.terminalHandle], cwd, env).terminal; }
function validatePreparedIdentity(api, c, state, env, requireCaller) {
  const checkout = c.checkout, interaction = c.interaction;
  if (checkout.owner !== 'orca') throw new Error('invalid checkout owner');
  if (typeof checkout.ownerId !== 'string' || checkout.ownerId.indexOf('::') < 1 || !checkout.ownerId.endsWith(`::${checkout.path}`)) throw new Error('invalid prepared worktree identity');
  if (!interaction.terminalHandle || (requireCaller && (env.ORCA_WORKTREE_ID !== checkout.ownerId || env.ORCA_TERMINAL_HANDLE !== interaction.terminalHandle))) throw new Error('prepared worktree/terminal mismatch');
  if (state?.handle !== interaction.terminalHandle || state.worktreeId !== checkout.ownerId || !state.connected || !state.writable || fs.realpathSync(state.worktreePath) !== fs.realpathSync(checkout.path)) throw new Error('live worktree/terminal identity mismatch');
}
function submit(api, c, prompt, cwd, save) {
  const receipt = result(api, ['terminal', 'send', '--terminal', c.interaction.terminalHandle, '--text', prompt, '--enter', '--wait-submit', '15'], cwd);
  save(receipt);
  if (receipt.send?.handle !== c.interaction.terminalHandle || receipt.send.accepted !== true) throw new Error('OMP prompt not accepted');
  return { receipt, status: receipt.send.prompt?.stages?.includes('turn_started') ? 'started' : 'accepted' };
}
module.exports = { binary, preflight, resolveRepository, createCheckout, startReviewer, ready, inspectIdentity, validatePreparedIdentity, submit };
