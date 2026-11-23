'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { resolveRepository, createCheckout } = require('./worktrunk.js');

const id = (value, kind) => typeof value === 'string' && new RegExp(`^${kind}:[a-zA-Z0-9-]+$`).test(value);
const prefix = ['--autostart=false', '--timeout', '5s'];
function json(api, args, cwd, env) {
  return api.jsonCommand('rex', [...prefix, ...args], cwd, env, 8000);
}
function who(api, cwd, env = process.env) {
  const live = json(api, ['whoami', '--json'], cwd, env);
  if (live.principal?.transport !== 'unix' || live.principal.uid !== process.getuid() || !live.instance_id || !live.host_id) throw new Error('verified local Rex server required');
  return live;
}
function inspectBlock(api, session, block, cwd, env) {
  return json(api, ['block', 'inspect', '-s', session, '--json', block], cwd, env);
}
function callArgs(i, method) { return ['block', 'call', '-s', i.sessionId, '-b', i.blockId, method]; }
function preflight(api) {
  for (const binary of ['rex', 'wt']) api.command('/usr/bin/env', ['which', binary]);
  const cwd = process.cwd(), { REX_SESSION: session, REX_BLOCK: block } = process.env;
  if (!id(session, 'session') || !id(block, 'block')) throw new Error('run pr-review from a local Rex terminal');
  const live = who(api, cwd);
  if (live.session_id !== session || live.block_id !== block) throw new Error('current Rex block identity unavailable');
  const help = api.command('rex', ['run', '--help']);
  for (const flag of ['--json', '--shell', '--focus', '--cwd', '--keep-open']) if (!help.includes(flag)) throw new Error('required Rex run options unavailable');
  const wt = api.command('wt', ['switch', '--help']);
  for (const flag of ['--no-cd', '--format', '--base']) if (!wt.includes(flag)) throw new Error('required Worktrunk options unavailable');
  const inspected = inspectBlock(api, session, block, cwd);
  for (const method of ['process', 'program_status', 'write']) if (!Object.hasOwn(inspected.api?.methods || {}, method)) throw new Error(`required Rex terminal method unavailable: ${method}`);
}
function inspectIdentity(api, c, cwd, env) {
  const i = c.interaction;
  if (!id(i.sessionId, 'session') || !id(i.windowId, 'window') || !id(i.blockId, 'block')) throw new Error('invalid Rex interaction identity');
  const server = who(api, cwd, env);
  if (server.instance_id !== i.instanceId || server.host_id !== i.hostId) throw new Error('Rex server identity changed');
  const { session_id, block } = inspectBlock(api, i.sessionId, i.blockId, cwd, env);
  if (session_id !== i.sessionId || block?.block_id !== i.blockId || block.window_id !== i.windowId || block.host_id !== i.hostId || block.label !== i.agentName) throw new Error('live Rex block identity mismatch');
  if (block.placement !== 'placed') throw new Error('Rex reviewer block not placed');
  return { server, process: json(api, callArgs(i, 'process'), cwd, env) };
}
function validateProcess(c, live) {
  const p = live.process.child;
  if (live.process.last_exit !== null || !p || p.name !== 'omp' || p.user_id !== process.getuid() || p.path !== c.interaction.executable || fs.realpathSync(p.cwd || '/') !== fs.realpathSync(c.checkout.path)) throw new Error('live Rex OMP process identity mismatch');
  return p;
}
function validatePreparedIdentity(api, c, live, env, requireCaller) {
  const i = c.interaction;
  if (c.checkout.owner !== 'worktrunk' || !c.checkout.ownerId || c.checkout.ownerId !== c.checkout.branch || i.agentKind !== 'omp' || !i.agentName || !Number.isSafeInteger(i.processId) || i.processId <= 0 || !path.isAbsolute(i.executable || '')) throw new Error('invalid Rex review identity');
  if (requireCaller && (env.REX_SESSION !== i.sessionId || env.REX_BLOCK !== i.blockId || live.server.session_id !== i.sessionId || live.server.block_id !== i.blockId)) throw new Error('prepared Rex caller identity mismatch');
  if (validateProcess(c, live).pid !== i.processId) throw new Error('Rex reviewer process changed');
  const sessions = path.join(c.artifactPath, 'sessions');
  let count = 0;
  function visit(dir) {
    api.checkPrivate(dir, true);
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, item.name);
      if (item.isDirectory()) visit(file);
      else {
        api.checkPrivate(file, false);
        if (item.name.endsWith('.jsonl')) count++;
      }
    }
  }
  visit(sessions);
  if (requireCaller && count !== 1) throw new Error('one private Rex OMP session required');
}
function status(api, i, cwd) {
  const { records } = json(api, callArgs(i, 'program_status'), cwd);
  return records?.find(r => !r.id && r.app === 'omp' && r.owner?.pid === i.processId && r.owner.name === 'omp')?.state;
}
function bindReviewer(api, c, blockId, cwd) {
  if (!id(blockId, 'block')) throw new Error('invalid reviewer block ID');
  const live = who(api, cwd);
  if (live.session_id !== process.env.REX_SESSION || live.block_id !== process.env.REX_BLOCK || blockId === live.block_id) throw new Error('verified Rex launcher and separate reviewer required');
  const { block } = inspectBlock(api, live.session_id, blockId, cwd);
  const executable = fs.realpathSync(api.command('/usr/bin/env', ['which', 'omp']));
  const i = c.interaction;
  Object.assign(i, { sessionId: live.session_id, windowId: block?.window_id, blockId, instanceId: live.instance_id,
    hostId: live.host_id, agentKind: 'omp', executable });
  const observed = inspectIdentity(api, c, cwd);
  i.processId = validateProcess(c, observed).pid;
  validatePreparedIdentity(api, c, observed, process.env, false);
  if (status(api, i, cwd) !== 'idle') throw new Error('Rex reviewer is not idle; inspect the existing block');
}
module.exports = { preflight, resolveRepository, createCheckout, bindReviewer, inspectIdentity, validatePreparedIdentity };
