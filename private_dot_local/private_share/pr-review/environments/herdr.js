'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { isDeepStrictEqual } = require('node:util');
const crypto = require('node:crypto');
function request(api, args, cwd, env = process.env, timeout) {
  const data = api.jsonCommand('herdr', args, cwd, env, timeout);
  if (data.error || !data.result) throw new Error('Herdr request failed');
  return data.result;
}
function attempt(args, cwd, record, timeout = 300000) {
  const response = spawnSync('herdr', args, { cwd, encoding: 'utf8', timeout, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout || response.stderr); } catch {}
  record(data?.result || data || { status: 'unknown' }, { exitCode: response.status, signal: response.signal, spawnError: response.error?.code || null });
  if (response.error || response.status !== 0 || data?.error || !data?.result) throw new Error('Herdr request failed; retain known resources and receipt');
  return data.result;
}
function socket(api, cwd, env = process.env) {
  const status = api.command('herdr', ['status', 'server'], cwd, env);
  const match = status.match(/^socket:\s*(.+)$/m);
  if (!match || !path.isAbsolute(match[1]) || !env.HERDR_SOCKET_PATH || fs.realpathSync(match[1]) !== fs.realpathSync(env.HERDR_SOCKET_PATH)) throw new Error('Herdr session socket mismatch');
  const stat = fs.statSync(match[1]);
  if (!stat.isSocket() || (process.getuid && stat.uid !== process.getuid())) throw new Error('Herdr live session socket is not caller-owned');
  return fs.realpathSync(match[1]);
}
function preflight(api) {
  if (process.env.HERDR_ENV !== '1') throw new Error('herdr-outside');
  if (!['darwin', 'linux'].includes(process.platform)) throw new Error('Herdr shell readiness inspection requires a local POSIX terminal');
  for (const binary of ['herdr', 'wt', 'ps', 'stty']) api.command('/usr/bin/env', ['which', binary]);
  const help = api.command('wt', ['switch', '--help']);
  for (const flag of ['--no-hooks', '--no-cd', '--format', '--base']) if (!help.includes(flag)) throw new Error('Worktrunk hook suppression unavailable');
  if (!api.command('herdr', ['workspace', 'create', '--help']).includes('--no-focus')) throw new Error('Herdr background workspace unavailable');
  if (!api.command('herdr', ['agent', 'start', '--help']).includes('omp')) throw new Error('Herdr OMP support unavailable');
  if (!/^omp: current\b/m.test(api.command('herdr', ['integration', 'status']))) throw new Error('current Herdr OMP identity integration required');
  socket(api, process.cwd());
}
function resolveRepository(api, options) {
  return fs.realpathSync(api.git(options.repoPath || process.cwd(), 'rev-parse', '--show-toplevel'));
}
function createCheckout(api, options, resources, fixed, cwd, persist) {
  // Worktrunk's no-hooks suppresses its lifecycle hooks; suppress Git's native
  // post-checkout hooks as well, without writing repository configuration.
  const env = { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.hooksPath', GIT_CONFIG_VALUE_0: '/dev/null' };
  const response = spawnSync('wt', ['-C', cwd, 'switch', '--create', resources.name, '--base', fixed.baseSha, '--no-cd', '--no-hooks', '--format', 'json'], { cwd, env, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
  let data; try { data = JSON.parse(response.stdout); } catch {}
  Object.assign(resources.checkout, { owner: 'worktrunk', path: data?.path || null, ownerId: data?.branch || null, branch: data?.branch || null }); persist();
  if (response.error || response.status !== 0 || data?.action !== 'created' || data.created_branch !== true || data.branch !== resources.name || !path.isAbsolute(data.path)) throw new Error('Worktrunk creation identity mismatch');
}
async function waitForShellInput(api, paneId, cwd) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const remaining = () => Math.max(1, Math.min(5000, deadline - Date.now()));
    const info = request(api, ['pane', 'process-info', '--pane', paneId], cwd, process.env, remaining()).process_info;
    if (info?.pane_id !== paneId) throw new Error('Herdr shell pane identity mismatch');
    const shell = info.foreground_processes?.find(process => process.pid === info.shell_pid);
    if (Number.isSafeInteger(info.shell_pid) && info.shell_pid > 0 && info.foreground_process_group_id === info.shell_pid && shell && ['zsh', 'bash'].includes(shell.name)) {
      const tty = api.command('ps', ['-p', String(info.shell_pid), '-o', 'tty='], cwd, process.env, remaining());
      if (!/^(?:ttys[0-9]+|pts\/[0-9]+)$/.test(tty)) throw new Error('Herdr shell controlling terminal unavailable');
      const mode = api.command('stty', [process.platform === 'darwin' ? '-f' : '-F', `/dev/${tty}`, '-a'], cwd, process.env, remaining());
      // A foreground shell alone can still be sourcing startup files. ZLE/readline
      // enables noncanonical, no-echo input only when it is ready to edit a line.
      if (/(?:^|\s)-icanon(?:\s|$)/.test(mode) && /(?:^|\s)-echo(?:\s|$)/.test(mode)) return { shellPid: info.shell_pid, tty };
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  const error = new Error('Herdr shell input readiness timed out'); error.code = 'SHELL_INPUT_TIMEOUT'; throw error;
}
async function configureShell(api, resources, run, cwd, launcherDir) {
  const script = path.join(run, 'shell-setup.sh'), acknowledgment = path.join(run, 'shell-setup-ready');
  const token = crypto.randomUUID();
  api.privateWrite(script, `umask 077\nexport PATH=${api.shellQuote(launcherDir + path.delimiter + process.env.PATH)}\nunset OMPCODE OMP_PROFILE PI_CODING_AGENT_DIR\nprintf '%s' ${api.shellQuote(token)} > ${api.shellQuote(acknowledgment)}\n`);
  const command = `. ${api.shellQuote(script)}`;
  if (Buffer.byteLength(command) > 1024) throw new Error('Herdr shell setup command exceeds safe input bound');
  const diagnostic = path.join(run, 'shell-setup-status.json');
  let phase = 'initial-shell-input';
  const record = (status, extra = {}) => fs.writeFileSync(diagnostic, JSON.stringify({ status, phase, paneId: resources.interaction.paneId, ...extra }, null, 2) + '\n', { mode: 0o600 });
  try {
    record('waiting');
    const initial = await waitForShellInput(api, resources.interaction.paneId, cwd);
    phase = 'setup-command'; record('ready', initial);
    // pane run is a text/exit-status CLI, unlike workspace and agent JSON commands.
    // Successful input submission is not execution proof; require the token below.
    const sent = spawnSync('herdr', ['pane', 'run', resources.interaction.paneId, command], { cwd, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
    let response; try { response = JSON.parse(sent.stdout || sent.stderr); } catch {}
    api.privateWrite(path.join(run, 'shell-setup-command.json'), { command, paneId: resources.interaction.paneId, exitCode: sent.status, signal: sent.signal, spawnError: sent.error?.code || null, errorCode: response?.error?.code || null });
    if (sent.error || sent.status !== 0 || response?.error) throw new Error('Herdr shell setup input failed; inspect retained receipt');
    phase = 'setup-acknowledgment'; record('waiting');
    const deadline = Date.now() + 30000;
    while (!fs.existsSync(acknowledgment) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 100));
    api.checkPrivate(acknowledgment, false);
    if (fs.readFileSync(acknowledgment, 'utf8') !== token) throw new Error('Herdr shell setup acknowledgment mismatch');
    phase = 'configured-shell-input'; record('waiting');
    const ready = await waitForShellInput(api, resources.interaction.paneId, cwd);
    record('ready', ready);
  } catch (error) {
    record('blocked', { code: error.code || 'SHELL_SETUP_FAILED' }); throw error;
  }
}
async function startReviewer(api, resources, run, cwd, persist, options) {
  const launcherDir = path.join(run, 'bin'); fs.mkdirSync(launcherDir, { mode: 0o700 });
  const realOmp = api.command('/usr/bin/env', ['which', 'omp']);
  if (!path.isAbsolute(realOmp) || fs.realpathSync(realOmp).startsWith(run + path.sep)) throw new Error('trusted OMP executable required');
  const launcher = path.join(launcherDir, 'omp');
  api.privateWrite(launcher, `#!/bin/sh\numask 077\nunset OMP_PROFILE PI_CODING_AGENT_DIR OMPCODE\nexec ${api.shellQuote(realOmp)} "$@"\n`); fs.chmodSync(launcher, 0o700);
  // Only a short source command crosses the PTY, after actual shell input readiness.
  // The private script holds the inherited PATH and acknowledges successful setup.
  const sessionSocket = socket(api, cwd);
  attempt(['workspace', 'create', '--cwd', resources.checkout.path, '--label', resources.name, options.noFocus ? '--no-focus' : '--focus'], cwd, workspace => {
    Object.assign(resources.interaction, { sessionSocket, workspaceId: workspace.workspace?.workspace_id || null, tabId: workspace.tab?.tab_id || null, paneId: workspace.root_pane?.pane_id || null, terminalId: workspace.root_pane?.terminal_id || null, agentName: resources.name, agentKind: 'omp' }); persist();
  });
  if (!resources.interaction.workspaceId || !resources.interaction.tabId || !resources.interaction.paneId || !resources.interaction.terminalId) throw new Error('incomplete Herdr workspace identity');
  await configureShell(api, resources, run, cwd, launcherDir);
  const started = attempt(['agent', 'start', resources.name, '--kind', 'omp', '--pane', resources.interaction.paneId, '--timeout', '120000', '--', '--cwd', resources.checkout.path, '--session-dir', path.join(run, 'sessions'), '--config', path.join(run, 'omp-config.yml')], cwd, response => {
    api.privateWrite(path.join(run, 'agent-start.json'), response);
    resources.interaction.agentSession = response.agent?.agent_session || null; persist();
  });
  const agent = started.agent;
  if (started.type !== 'agent_started' || agent?.interactive_ready !== true || agent?.agent !== 'omp' || agent?.name !== resources.name) throw new Error('Herdr reviewer readiness not proven');
}
function inspectIdentity(api, c, cwd, env) {
  return { sessionSocket: socket(api, cwd, env), agent: request(api, ['agent', 'get', c.interaction.paneId], cwd, env).agent, process: request(api, ['pane', 'process-info', '--pane', c.interaction.paneId], cwd, env).process_info };
}
function validatePreparedIdentity(api, c, live, env, requireCaller) {
  const i = c.interaction, checkout = c.checkout;
  if (checkout.owner !== 'worktrunk' || !checkout.ownerId || checkout.ownerId !== checkout.branch) throw new Error('invalid checkout owner identity');
  if (requireCaller && (env.HERDR_ENV !== '1' || env.HERDR_PANE_ID !== i.paneId || env.HERDR_WORKSPACE_ID !== i.workspaceId || env.HERDR_TAB_ID !== i.tabId)) throw new Error('prepared Herdr pane identity mismatch');
  const a = live.agent;
  if (live.sessionSocket !== i.sessionSocket || !a || a.workspace_id !== i.workspaceId || a.tab_id !== i.tabId || a.pane_id !== i.paneId || a.terminal_id !== i.terminalId || a.name !== i.agentName || i.agentKind !== 'omp' || a.agent !== 'omp' || !isDeepStrictEqual(a.agent_session, i.agentSession)) throw new Error('live Herdr agent identity mismatch');
  if (!['idle', 'working', 'done', 'blocked'].includes(a.agent_status) || fs.realpathSync(a.foreground_cwd) !== fs.realpathSync(checkout.path)) throw new Error('live Herdr cwd/readiness mismatch');
  const session = i.agentSession;
  if (session?.agent !== 'omp' || session.kind !== 'path' || session.source !== 'herdr:omp' || !path.isAbsolute(session.value) || fs.realpathSync(path.dirname(session.value)) !== fs.realpathSync(path.join(c.artifactPath, 'sessions'))) throw new Error('private Herdr agent session mismatch');
  api.checkPrivate(path.join(c.artifactPath, 'sessions'), true);
  // OMP names its session at startup but persists it only after the first prompt.
  // Bootstrap checks the private parent; prepared execution must check the file.
  if (requireCaller || fs.existsSync(session.value)) api.checkPrivate(session.value, false);
  const p = live.process;
  if (p?.pane_id !== i.paneId || !p.foreground_processes?.some(process => {
    const argv = process.argv || [];
    return process.cwd && fs.realpathSync(process.cwd) === fs.realpathSync(checkout.path) && argv.includes('--cwd') && argv[argv.indexOf('--cwd') + 1] === checkout.path && argv.includes('--session-dir') && argv[argv.indexOf('--session-dir') + 1] === path.join(c.artifactPath, 'sessions') && argv.includes('--config') && argv[argv.indexOf('--config') + 1] === path.join(c.artifactPath, 'omp-config.yml');
  })) throw new Error('live Herdr process identity mismatch');
}
function submit(api, c, prompt, cwd, save) {
  const receipt = attempt(['agent', 'prompt', c.interaction.paneId, prompt], cwd, save);
  if (receipt.type !== 'agent_prompted' || receipt.agent?.pane_id !== c.interaction.paneId || receipt.agent?.terminal_id !== c.interaction.terminalId || !isDeepStrictEqual(receipt.agent?.agent_session, c.interaction.agentSession)) throw new Error('Herdr prompt acceptance unproven');
  // agent_prompted acknowledges input only; it is not turn-start evidence.
  return { receipt, status: 'accepted' };
}
module.exports = { preflight, resolveRepository, createCheckout, startReviewer, inspectIdentity, validatePreparedIdentity, submit };
