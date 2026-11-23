'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function get(api, address, cwd, env = process.env) {
  return api.jsonCommand('hc', ['get', '--json', address], cwd, env);
}
function preflight(api) {
  for (const binary of ['hc', 'wt']) api.command('/usr/bin/env', ['which', binary]);
  const help = api.command('wt', ['switch', '--help']);
  for (const flag of ['--no-cd', '--format', '--base']) if (!help.includes(flag)) throw new Error('required Worktrunk options unavailable');
  if (process.env.HC_TERMINAL_ID) {
    const caller = get(api, process.env.HC_TERMINAL_ID, process.cwd());
    if (caller.address !== process.env.HC_TERMINAL_ID || caller.state !== 'live' || !caller.foreground || !path.isAbsolute(caller.foreground.cwd || '') || !Number.isSafeInteger(caller.foreground.pid) || caller.foreground.pid <= 0) throw new Error('current core terminal identity unavailable');
  }
}
const { resolveRepository, createCheckout } = require('./worktrunk.js');
function startReviewer(api, resources, run, cwd, persist) {
  const omp = api.command('/usr/bin/env', ['which', 'omp']);
  if (!path.isAbsolute(omp)) throw new Error('absolute OMP executable required');
  const args = ['env', '-u', 'OMP_PROFILE', '-u', 'PI_CODING_AGENT_DIR', '-u', 'OMPCODE', `PATH=${process.env.PATH || ''}`, omp, '--cwd', resources.checkout.path, '--session-dir', path.join(run, 'sessions'), '--config', path.join(run, 'omp-config.yml')];
  const script = `umask 077; exec ${args.map(api.shellQuote).join(' ')}`;
  const response = spawnSync('hc', ['run', '--json', '--bg', '--no-parent', '--name', resources.name, '--cwd', resources.checkout.path, '--', '/bin/sh', '-c', script], { cwd, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  Object.assign(resources.interaction, { terminalId: data?.address || null, createdMs: null, agentName: resources.name, agentKind: 'omp', processId: null }); persist();
  if (response.error || response.status !== 0 || !/^t[0-9a-z]+$/.test(data?.address || '') || data.name !== resources.name) throw new Error('core terminal creation unproven; retain recorded resources');
  const created = get(api, data.address, cwd);
  if (created.address !== data.address || created.name !== resources.name || created.state !== 'live' || !Number.isSafeInteger(created.created_ms)) throw new Error('core terminal identity unproven');
  resources.interaction.createdMs = created.created_ms; persist();
  const deadline = Date.now() + 120000;
  for (;;) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error('core reviewer readiness unproven');
    api.jsonCommand('hc', ['wait', '--json', '--timeout', String(Math.ceil(remaining / 1000)), data.address], cwd, process.env, remaining + 10000);
    const live = get(api, data.address, cwd);
    if (live.address !== data.address || live.created_ms !== created.created_ms || live.name !== resources.name || live.state !== 'live') throw new Error('core reviewer identity changed');
    if (live.status?.app === 'omp' && live.status?.state === 'idle' && Number.isSafeInteger(live.foreground?.pid) && live.foreground.pid > 0) {
      resources.interaction.processId = live.foreground.pid; persist();
      break;
    }
    if (['blocked', 'error'].includes(live.status?.state)) throw new Error('core reviewer readiness unproven');
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Math.min(100, Math.max(0, deadline - Date.now())));
  }
}
function inspectIdentity(api, c, cwd, env) { return get(api, c.interaction.terminalId, cwd, env); }
function validatePreparedIdentity(api, c, live, env, requireCaller) {
  const i = c.interaction, checkout = c.checkout;
  if (checkout.owner !== 'worktrunk' || !checkout.ownerId || checkout.ownerId !== checkout.branch) throw new Error('invalid checkout owner identity');
  if (!/^t[0-9a-z]+$/.test(i.terminalId || '') || !Number.isSafeInteger(i.createdMs) || !Number.isSafeInteger(i.processId) || i.processId <= 0 || i.agentKind !== 'omp' || !i.agentName) throw new Error('invalid core interaction identity');
  if (requireCaller && env.HC_TERMINAL_ID !== i.terminalId) throw new Error('prepared core caller identity mismatch');
  if (live.address !== i.terminalId || live.created_ms !== i.createdMs || live.name !== i.agentName || live.state !== 'live' || live.status?.app !== 'omp' || !['idle', 'working', 'done', 'blocked'].includes(live.status?.state) || live.foreground?.pid !== i.processId || fs.realpathSync(live.foreground.cwd) !== fs.realpathSync(checkout.path)) throw new Error('live core terminal identity mismatch');
  const argv = live.foreground.argv;
  if (!Array.isArray(argv) || ![['--cwd', checkout.path], ['--session-dir', path.join(c.artifactPath, 'sessions')], ['--config', path.join(c.artifactPath, 'omp-config.yml')]].every(([flag, value]) => argv.includes(flag) && argv[argv.indexOf(flag) + 1] === value)) throw new Error('live core process arguments mismatch');
  const sessions = path.join(c.artifactPath, 'sessions');
  api.checkPrivate(sessions, true);
  api.checkPrivate(path.join(c.artifactPath, 'omp-config.yml'), false);
  const entries = fs.readdirSync(sessions, { withFileTypes: true });
  if (requireCaller && entries.filter(entry => entry.isFile() && !entry.name.startsWith('.') && entry.name.endsWith('.jsonl')).length !== 1) throw new Error('one private core agent session required');
  function checkEntries(dir, children) {
    for (const entry of children) {
      const file = path.join(dir, entry.name);
      const directory = entry.isDirectory();
      api.checkPrivate(file, directory);
      if (directory) checkEntries(file, fs.readdirSync(file, { withFileTypes: true }));
    }
  }
  checkEntries(sessions, entries);
}
function submit(api, c, prompt, cwd, save) {
  const response = spawnSync('hc', ['send', '--json', '--if', 'idle', c.interaction.terminalId, prompt], { cwd, encoding: 'utf8', timeout: 120000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  const receipt = { terminalId: c.interaction.terminalId, exitCode: response.status, signal: response.signal, spawnError: response.error?.code || null, result: data || null };
  save(receipt);
  if (response.error || response.status !== 0 || !data || !Number.isSafeInteger(data.turn) || data.status !== 'idle') throw new Error('core prompt acceptance unproven; inspect retained terminal and receipt');
  return { receipt, status: data.started === true ? 'started' : 'accepted' };
}
module.exports = { preflight, resolveRepository, createCheckout, startReviewer, inspectIdentity, validatePreparedIdentity, submit };
