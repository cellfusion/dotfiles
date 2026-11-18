import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { truncateToWidth, visibleWidth } from '@earendil-works/pi-tui';
import { homedir } from 'node:os';
import { contextBar, parseGitStatus, sessionCosts, thinkingIcon, worktreeName } from './helpers.mjs';

const clean = (s: string) => s.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');
const color = (rgb: string, s: string) => `\x1b[38;2;${rgb}m${s}\x1b[39m`;
const green = (s: string) => color('140;230;100', s);
const orange = (s: string) => color('255;174;66', s);
const gold = (s: string) => color('220;201;146', s);

export default function (pi: ExtensionAPI) {
  let timer: ReturnType<typeof setInterval> | undefined;
  let stopped = false;
  let refreshing = false;
  let worktree = '';
  let counts = { changed: 0, untracked: 0 };
  let requestRender = () => {};

  pi.on('session_start', async (_event, ctx) => {
    if (ctx.mode !== 'tui') return;
    stopped = false;
    const started = Date.now();
    const updateGit = async () => {
      if (refreshing || stopped) return;
      refreshing = true;
      try {
        const root = await pi.exec('git', ['rev-parse', '--show-toplevel'], { cwd: ctx.cwd, timeout: 3000 });
        const dirs = root.code === 0
          ? await pi.exec('git', ['rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir'], { cwd: ctx.cwd, timeout: 3000 })
          : undefined;
        const status = root.code === 0
          ? await pi.exec('git', ['status', '--porcelain=v1', '-z', '--untracked-files=normal'], { cwd: ctx.cwd, timeout: 5000, maxBuffer: 4 * 1024 * 1024 })
          : undefined;
        if (!stopped) {
          worktree = root.code === 0 && dirs?.code === 0 ? worktreeName(root.stdout.trim(), dirs.stdout) : '';
          counts = status?.code === 0 && !status.truncated ? parseGitStatus(status.stdout) : { changed: 0, untracked: 0 };
          requestRender();
        }
      } catch { /* Git may be unavailable, or the directory may not be a repository. */ }
      finally { refreshing = false; }
    };
    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(() => { void updateGit(); tui.requestRender(); });
      return {
        dispose() { unsubscribe(); requestRender = () => {}; },
        invalidate() {},
        render(width: number) {
          const sep = theme.fg('dim', '  ');
          const home = homedir();
          const path = ctx.cwd === home ? '~' : ctx.cwd.startsWith(home + '/') ? `~${ctx.cwd.slice(home.length)}` : ctx.cwd;
          const mins = Math.floor((Date.now() - started) / 60000);
          const model = ctx.model?.name || ctx.model?.id || 'no model';
          const parts = [green(`${mins}m`), green(`${thinkingIcon(ctx.thinkingLevel)} ${clean(model)}`), theme.fg('text', ` ${clean(path)}`)];
          if (worktree) parts.push(theme.fg('text', ` ${clean(worktree)}`));
          const branch = footerData.getGitBranch();
          if (branch) parts.push(orange(` ${clean(branch)}${counts.changed ? ` *${counts.changed}` : ''}${counts.untracked ? ` ?${counts.untracked}` : ''}`));
          const costs = sessionCosts(ctx.sessionManager.getBranch());
          if (costs.latest !== undefined) parts.push(gold(`󰙺 $${costs.total.toFixed(2)} (+$${costs.latest.toFixed(2)})`));
          const left = parts.join(sep) + theme.fg('dim', ' ');
          const percent = ctx.getContextUsage()?.percent ?? null;
          const remaining = width - visibleWidth(left) - 1;
          const first = remaining >= 8
            ? left + ' ' + green(contextBar(percent, remaining))
            : truncateToWidth(left, width);
          const statuses = [...footerData.getExtensionStatuses().values()];
          return [truncateToWidth(first, width), ...statuses.map((s) => truncateToWidth(s.replace(/[\r\n]/g, ' '), width))];
        },
      };
    });
    void updateGit();
    timer = setInterval(() => { void updateGit(); requestRender(); }, 10000);
  });
  pi.on('session_shutdown', () => {
    stopped = true;
    if (timer) clearInterval(timer);
    timer = undefined;
  });
}
