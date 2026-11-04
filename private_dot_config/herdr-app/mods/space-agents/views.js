const ORDER = ["blocked", "done", "working", "idle"];

export function urgentStatus(statuses) {
  for (const status of ORDER) if (statuses.includes(status)) return status;
  return null;
}

export function buildGroups(rows, tags, view, statusesOf) {
  const query = (view.query ?? "").trim().toLocaleLowerCase();
  const filtered = rows.filter(({ w }) => {
    const mine = tags[w.id] ?? [];
    const statuses = statusesOf(w);
    return (!query || w.name.toLocaleLowerCase().includes(query) || mine.some(t => t.toLocaleLowerCase().includes(query)))
      && (!view.tag || mine.includes(view.tag))
      && (!view.status || (view.status === "none" ? !statuses.length : statuses.includes(view.status)));
  });
  if (view.group === "tag") {
    const groups = new Map();
    for (const row of filtered) for (const tag of tags[row.w.id]?.length ? tags[row.w.id] : [null]) {
      if (!groups.has(tag)) groups.set(tag, []);
      groups.get(tag).push(row);
    }
    return [...groups.entries()].sort(([a], [b]) => a === null ? 1 : b === null ? -1 : a.localeCompare(b))
      .map(([key, rows]) => ({ key, rows }));
  }
  if (view.group === "status") {
    return [...ORDER, "none"].map(key => ({ key, rows: filtered.filter(({ w }) => (urgentStatus(statusesOf(w)) ?? "none") === key) }))
      .filter(group => group.rows.length);
  }
  return [{ key: "all", rows: filtered }];
}
