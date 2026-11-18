import { basename } from 'node:path';

export function worktreeName(root, gitDirs) {
  const [gitDir, commonDir] = gitDirs.trim().split('\n');
  return gitDir && commonDir && gitDir !== commonDir ? basename(root) : '';
}

export function parseGitStatus(output) {
  let changed = 0, untracked = 0;
  const records = output.split('\0');
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    if (!record) continue;
    const status = record.slice(0, 2);
    if (status === '??') untracked++;
    else {
      changed++;
      if (status.includes('R') || status.includes('C')) i++;
    }
  }
  return { changed, untracked };
}

export function thinkingIcon(level) {
  return ({ off: '', none: '', auto: '', minimal: '󰪟', low: '󰪟', medium: '󰪡', high: '󰪣', xhigh: '󰪥', max: '' })[level] ?? '';
}

export function sessionCosts(entries) {
  let total = 0, latest;
  for (const entry of entries) {
    if (entry.type !== 'message') continue;
    const msg = entry.message;
    const cost = msg.usage?.cost?.total;
    if (typeof cost !== 'number' || !Number.isFinite(cost)) continue;
    total += cost;
    if (msg.role === 'assistant') latest = cost;
  }
  return { total, latest };
}

export function contextBar(percent, width) {
  const value = typeof percent === 'number' && Number.isFinite(percent) ? Math.max(0, Math.min(100, percent)) : null;
  const label = value === null ? ' ? ' : `${Math.round(value)}%`;
  if (width <= label.length) return label.slice(0, width);
  const remainder = width - label.length;
  const filled = value === null ? 0 : Math.round(remainder * value / 100);
  return '━'.repeat(filled) + label + '─'.repeat(remainder - filled);
}
