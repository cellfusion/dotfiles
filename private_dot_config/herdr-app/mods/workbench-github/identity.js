export function itemKey({ host, owner, repo, kind, number }) {
  return JSON.stringify([host, owner, repo, kind, number]);
}
