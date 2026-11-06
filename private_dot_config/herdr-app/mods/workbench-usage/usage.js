const finite = (value) => typeof value === "number" && Number.isFinite(value);

function windowName(window, label) {
  const duration = window?.durationMs;
  if (finite(duration) && duration > 0) {
    if (duration % 86400000 === 0) return `${duration / 86400000}d`;
    if (duration % 3600000 === 0) return `${duration / 3600000}h`;
    if (duration % 60000 === 0) return `${duration / 60000}m`;
  }
  const named = typeof window?.label === "string" ? window.label : typeof label === "string" ? label : "";
  const value = named.trim().toLowerCase().replace(/\s+/g, " ");
  return ({ "5 hours": "5h", "5 hour": "5h", "5h": "5h", "7 days": "7d", "7 day": "7d", "7d": "7d", "1w": "7d", weekly: "7d",
    "24 hours": "1d", "24h": "1d", "1d": "1d", daily: "1d", "30 days": "30d", "30d": "30d", monthly: "month", session: "session" })[value] ?? "";
}

// OMP's normalized report uses usedFraction first, then used/limit, then
// percent-unit used. Remaining fraction is a last-resort reported measure.
export function parseUsage(text) {
  const data = JSON.parse(text);
  const rows = [];
  const reports = [...(Array.isArray(data?.reports) ? data.reports : []),
    ...(Array.isArray(data?.accountsWithoutUsage) ? data.accountsWithoutUsage : [])]
    .filter(report => report && typeof report.provider === "string");
  const totals = new Map(), seen = new Map();
  for (const report of reports) totals.set(report.provider, (totals.get(report.provider) ?? 0) + 1);
  for (const report of reports) {
    const account = (seen.get(report.provider) ?? 0) + 1, accounts = totals.get(report.provider);
    seen.set(report.provider, account);
    let added = false;
    for (const limit of Array.isArray(report.limits) ? report.limits : []) {
      if (!limit || typeof limit !== "object") continue;
      const amount = limit.amount ?? {};
      let usedPercent;
      if (finite(amount.usedFraction)) usedPercent = amount.usedFraction * 100;
      else if (finite(amount.used) && finite(amount.limit) && amount.limit > 0) usedPercent = amount.used / amount.limit * 100;
      else if (finite(amount.used) && amount.unit === "percent") usedPercent = amount.used;
      else if (finite(amount.used) && amount.unit === "fraction") usedPercent = amount.used * 100;
      else if (finite(amount.remainingFraction)) usedPercent = Math.max(0, 1 - amount.remainingFraction) * 100;
      if (!finite(usedPercent)) usedPercent = null;
      added = true;
      rows.push({
        provider: report.provider,
        label: typeof limit.label === "string" ? limit.label : "",
        usedPercent,
        resetsAt: finite(limit.window?.resetsAt) ? limit.window.resetsAt : null,
        status: ["ok", "warning", "exhausted", "unknown"].includes(limit.status) ? limit.status : null,
        window: windowName(limit.window, limit.label),
        account,
        accounts,
      });
    }
    if (!added) rows.push({ provider: report.provider, label: "", usedPercent: null, resetsAt: null, status: null, window: "", account, accounts });
  }
  return rows;
}
