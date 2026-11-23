'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function resolveRepository(api, options) {
  return fs.realpathSync(api.git(options.repoPath || process.cwd(), 'rev-parse', '--show-toplevel'));
}
function requireApprovals(api, cwd, resources) {
  let data;
  try { data = api.jsonCommand('wt', ['-C', cwd, 'config', 'approvals', 'list', '--format', 'json'], cwd); } catch {}
  if (!['approved', 'no_commands'].includes(data?.state) || !Array.isArray(data.commands) || data.commands.some(command => command.approved !== true) || (data.state === 'no_commands' && data.commands.length !== 0)) {
    resources.lifecycleError = 'Worktrunk project approvals are unresolved; retain resources and resolve approvals explicitly.';
    throw new Error('Worktrunk approvals unresolved');
  }
}
function createCheckout(api, options, resources, fixed, cwd, persist) {
  requireApprovals(api, cwd, resources);
  const env = { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.hooksPath', GIT_CONFIG_VALUE_0: '/dev/null' };
  const response = spawnSync('wt', ['-C', cwd, 'switch', '--create', resources.name, '--base', fixed.baseSha, '--no-cd', '--format', 'json'], { cwd, env, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  Object.assign(resources.checkout, { owner: 'worktrunk', path: data?.path || null, ownerId: data?.branch || null, branch: data?.branch || null }); persist();
  if (response.error || response.status !== 0 || data?.action !== 'created' || data.created_branch !== true || data.branch !== resources.name || !path.isAbsolute(data.path || '')) throw new Error('Worktrunk creation identity mismatch');
  requireApprovals(api, data.path, resources);
}
module.exports = { resolveRepository, createCheckout };
