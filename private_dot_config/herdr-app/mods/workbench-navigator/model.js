export function selectAgentAction(address, terminals, panes) {
  if (!address || !terminals.some(t => t.address === address && t.state === "live")) return null;
  return { name: panes.some(p => p.terminal === address) ? "agent.focus" : "terminal.peek", args: { terminal: address } };
}

// Core addresses are already machine-qualified; never equate a bare address with a remote one.
export function collectEntries(spaces, panes, agents, terminals) {
  const byAddress = new Map();
  const terminalMap = new Map(terminals.filter(t => t.state === "live").map(t => [t.address, t]));
  const spaceByTab = new Map();
  for (const space of spaces) for (const tab of space.tabs ?? []) spaceByTab.set(tab.id, space);
  const paneMap = new Map(panes.filter(p => p.terminal).map(p => [p.terminal, p]));
  const spaceMap = new Map(spaces.map(s => [s.id, s]));
  for (const pane of panes) {
    if (!pane.terminal || !terminalMap.has(pane.terminal)) continue;
    const space = spaceByTab.get(pane.tab);
    if (!space) continue;
    const terminal = terminalMap.get(pane.terminal);
    byAddress.set(pane.terminal, { address: pane.terminal, space, pane, terminal, cwd: pane.cwd || null, branch: pane.branch || null, status: pane.status, title: pane.title || terminal.name || pane.terminal, program: pane.program?.name || terminal.program?.name || null, app: pane.app || null, agent: Boolean(pane.status || pane.program?.agent || terminal.program?.agent), parent: terminal.parent || null });
  }
  for (const agent of agents) {
    const terminal = terminalMap.get(agent.address), space = spaceMap.get(agent.space);
    if (!terminal || !space) continue;
    const pane = paneMap.get(agent.address);
    const cwd = pane?.cwd || (typeof terminal.cwd === "string" && terminal.cwd ? terminal.cwd : null);
    byAddress.set(agent.address, { address: agent.address, space, pane, terminal, cwd, branch: pane?.branch || null, status: agent.status, title: agent.title || agent.program?.name || agent.address, program: agent.program?.name || pane?.program?.name || terminal.program?.name || null, app: agent.app || pane?.app || null, agent: true, parent: terminal.parent || null });
  }
  // A parent link is evidence of ownership, not of a child's working directory.
  // Include descendants only when the reported parent is actually present.
  let added = true;
  while (added) {
    added = false;
    for (const terminal of terminals) {
      if (terminal.state !== "live" || !terminal.address || byAddress.has(terminal.address) || !terminal.parent) continue;
      const machineOf = address => address.includes("/") ? address.slice(0, address.indexOf("/")) : null;
      if (machineOf(terminal.address) !== machineOf(terminal.parent)) continue;
      const parent = byAddress.get(terminal.parent);
      if (!parent) continue;
      const cwd = typeof terminal.cwd === "string" && terminal.cwd ? terminal.cwd : null;
      byAddress.set(terminal.address, { address: terminal.address, space: parent.space, pane: null, terminal, cwd, branch: null, status: terminal.status || null, title: terminal.title || terminal.name || terminal.program?.name || terminal.address, program: terminal.program?.name || null, app: null, agent: Boolean(terminal.status || terminal.program?.agent), parent: terminal.parent });
      added = true;
    }
  }
  return [...byAddress.values()];
}

// Worktrees from the same verified common Git directory belong to one project.
// Unknown locations remain explicit categories rather than guessed repositories.
export function groupProjects(entries, infoFor) {
  const groups = new Map();
  for (const entry of entries) {
    const info = infoFor(entry), machine = entry.space.machine ?? null;
    const key = JSON.stringify([machine, info.kind, info.kind === "repo" ? info.repo : null]);
    if (!groups.has(key)) groups.set(key, { key, machine, info, entries: [] });
    groups.get(key).entries.push(entry);
  }
  return [...groups.values()];
}

export function agentSummary(entries) {
  const unique = new Map();
  for (const entry of entries) if (entry.agent) unique.set(entry.address, entry);
  const agents = [...unique.values()];
  return {
    total: agents.length,
    working: agents.filter(entry => entry.status === "working").length,
    blocked: agents.filter(entry => entry.status === "blocked").length,
    done: agents.filter(entry => entry.status === "done").length,
    error: agents.filter(entry => entry.status === "error").length,
  };
}

export function groupPriority(entries) {
  let priority = 3;
  for (const entry of entries) {
    if (!entry.agent) continue;
    if (entry.status === "blocked" || entry.status === "error") return 0;
    if (entry.status === "done") priority = Math.min(priority, 1);
    else if (entry.status === "working") priority = Math.min(priority, 2);
  }
  return priority;
}

export function workspaceEntries(allSpaces, allPanes, allAgents, allTerminals) {
  const entries = collectEntries(allSpaces, allPanes, allAgents, allTerminals);
  const occupied = new Set(entries.map(entry => entry.space.id));
  for (const space of allSpaces) if (!occupied.has(space.id))
    entries.push({ space, address: null, cwd: typeof space.folder === "string" && space.folder ? space.folder : null, branch: null, title: space.name, agent: false, status: null });
  return entries;
}

// Never substitute another terminal when the first terminal's cwd is unknown.
export function workspaceLocations(allSpaces, allPanes, allTerminals, allAgents) {
  const live = new Set(allTerminals.filter(terminal => terminal.state === "live").map(terminal => terminal.address));
  const firstByTab = new Map();
  const paneAddresses = new Set(allPanes.filter(pane => pane.terminal).map(pane => pane.terminal));
  // An agent reported without its pane leaves the tab's first terminal uncertain.
  for (const agent of allAgents) if (agent.tab && agent.address && !paneAddresses.has(agent.address))
    firstByTab.set(agent.tab, null);
  for (const pane of allPanes) {
    if (pane.tab && pane.terminal && !firstByTab.has(pane.tab))
      firstByTab.set(pane.tab, live.has(pane.terminal) ? (pane.cwd || null) : null);
  }
  const locations = new Map();
  for (const space of allSpaces) {
    const firstTab = (space.tabs ?? []).find(tab => firstByTab.has(tab.id));
    const cwd = firstTab ? firstByTab.get(firstTab.id) : (typeof space.folder === "string" && space.folder ? space.folder : null);
    locations.set(space.id, cwd);
  }
  return locations;
}
