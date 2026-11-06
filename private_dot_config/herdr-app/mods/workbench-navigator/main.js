import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, Input, InputState } from "gpui-base";
import { spaces, panes, agents, terminals, machines, exec, run, openOverlay, setAgentOrder, settings, theme, nextCommand, layout, shared, setShared, window, props } from "herdr";
import { agentSummary, groupPriority, groupProjects, selectAgentAction, workspaceEntries, workspaceLocations } from "./model.js";
import { WorkbenchPicker } from "./picker.js";

const TTL = 60000;
const GROUP_REPOSITORIES = "workbench.navigator.groupByRepository";
const machineKey = machine => machine ?? null;
const locationKey = (machine, cwd) => JSON.stringify([machineKey(machine), cwd]);
const base = path => path.replace(/[\\/]+$/, "").split(/[\\/]/).pop() || path;
const icon = name => svg(`mods/workspace-chrome/${name}.svg`).size(12).flex_none();
const projectLabel = info => info.kind === "repo"
  ? base(info.repo.endsWith("/.git") ? info.repo.slice(0, -5) : info.repo.replace(/\.git$/, ""))
  : ({ offline: "Machine unavailable", unknown: "Unknown directory", loading: "Checking repository…", inaccessible: "Repository inaccessible or ambiguous", "not-repository": "Not a repository" })[info.kind];
const statusLabel = status => ({ blocked: "Blocked", done: "Done · unseen", working: "Working", idle: "Idle", error: "Error" })[status] || (status || "Terminal");
const branchName = space => typeof space?.branch === "string" && space.branch ? space.branch : null;
const summaryText = count => [count.working ? `${count.working} working` : null, count.blocked ? `${count.blocked} blocked` : null, count.done ? `${count.done} unseen` : null, count.error ? `${count.error} errors` : null].filter(Boolean).join(" · ");
const urgentStatus = status => status === "blocked" || status === "error";
const rgb = color => typeof color === "string" && /^#[0-9a-f]{6}$/i.test(color)
  ? [1, 3, 5].map(index => parseInt(color.slice(index, index + 2), 16)) : null;
const luminance = channels => {
  const [r, g, b] = channels.map(value => {
    const v = value / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return r * 0.2126 + g * 0.7152 + b * 0.0722;
};
let lastPaletteKey, lastPalette;
function statusPalette(t) {
  const key = [t.foreground, t.chrome, t.selected, t.hover, t.blocked, t.done, t.working].join("|");
  if (key === lastPaletteKey) return lastPalette;
  const foreground = rgb(t.foreground), backgrounds = [t.chrome, t.selected, t.hover].map(rgb);
  const readable = color => {
    const source = rgb(color);
    if (!source || !foreground || backgrounds.some(value => !value)) return color;
    const levels = backgrounds.map(luminance);
    const score = value => {
      const light = luminance(value);
      return Math.min(...levels.map(background => (Math.max(light, background) + 0.05) / (Math.min(light, background) + 0.05)));
    };
    let best = source, bestScore = score(source);
    if (bestScore >= 4.5) return color;
    for (let step = 1; step <= 20; step++) {
      const candidate = source.map((value, index) => Math.round(value + (foreground[index] - value) * step / 20));
      const candidateScore = score(candidate);
      if (candidateScore > bestScore) { best = candidate; bestScore = candidateScore; }
      if (candidateScore >= 4.5) break;
    }
    return `#${best.map(value => value.toString(16).padStart(2, "0")).join("")}`;
  };
  lastPaletteKey = key;
  lastPalette = { foreground: t.foreground, blocked: readable(t.blocked), done: readable(t.done), working: readable(t.working) };
  return lastPalette;
}
const workspaceTone = (entries, t) => [t.blocked, t.done, t.working, t.foreground][groupPriority(entries)];
const currentReport = entry => entry.agent && entry.status && entry.terminal?.report?.state === entry.status ? entry.terminal.report : null;
const statusMessage = entry => {
  const message = currentReport(entry)?.msg;
  return typeof message === "string" ? message.slice(0, 512).replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim() : "";
};
// Git appends one LF; a second line, invalid UTF-8 replacement or control
// separator makes the path ambiguous. Spaces belong to the path.
const gitPath = output => {
  if (typeof output !== "string" || !output.endsWith("\n")) return null;
  const path = output.slice(0, -1);
  return path && !/[\r\n\0\uFFFD]/.test(path) ? path : null;
};

export default class WorkbenchNavigator extends View {
  init(_props, cx) {
    if (props()?.overlay) {
      this.picker = new WorkbenchPicker();
      this.picker.init(cx);
      return;
    }
    this.mode = "projects";
    this.filter = "all";
    this.narrow = false;
    this.compact = false;
    this.folded = new Set();
    this.opened = new Set();
    this.transientFolded = new Set();
    this.locations = new Map();
    this.inFlight = 0;
    this.error = null;
    this.search = InputState.new({ placeholder: "Search projects, spaces, agents" });
    this.search.on("change", (_e, context) => { this.transientFolded.clear(); context.notify(); });
    cx.spawn(async context => {
      for (;;) {
        if (await nextCommand() === "attention") {
          this.mode = "agents";
          this.filter = "attention";
          this.search.set_value("");
          this.search.focus();
          context.notify();
        }
      }
    });
    this.refresh(cx);
    cx.timer.every(3000, context => this.refresh(context));
  }
  close() { this.picker?.close(); }


  refresh(cx) {
    const currentMachines = machines();
    const allSpaces = spaces(), allPanes = panes(), allTerminals = terminals(), allAgents = agents();
    const entries = workspaceEntries(allSpaces, allPanes, allAgents, allTerminals);
    const workspaceCwds = workspaceLocations(allSpaces, allPanes, allTerminals, allAgents);
    const keys = new Map();
    for (const entry of entries) {
      const machine = machineKey(entry.space.machine);
      if (currentMachines.find(m => m.name === machine)?.layout !== "ready") continue;
      for (const cwd of [entry.cwd, workspaceCwds.get(entry.space.id)]) {
        if (typeof cwd === "string" && cwd) keys.set(locationKey(machine, cwd), { machine, cwd });
      }
    }
    for (const key of this.locations.keys()) if (!keys.has(key)) this.locations.delete(key);
    // Retain metadata for every active location; inactive records are removed
    // above. Only process concurrency, not the active set, is bounded.
    for (const [key, location] of keys) {
      if (!this.locations.has(key))
        this.locations.set(key, { ...location, pending: false, result: null });
    }
    const due = [...this.locations].filter(([, location]) =>
      !location.pending && (!location.result || Date.now() - location.result.at >= TTL));
    // Unresolved locations come first. Among expired results, refresh the
    // oldest accepted result first, so slow sweeps cannot recycle the front.
    due.sort((a, b) => {
      const left = a[1].result, right = b[1].result;
      if (!left || !right) return Number(Boolean(left)) - Number(Boolean(right));
      return left.at - right.at;
    });
    for (const [key, location] of due) {
      if (this.inFlight >= 4) break;
      location.pending = true;
      this.inFlight++;
      cx.spawn(async taskCx => {
        let value;
        try {
          const options = { cwd: location.cwd, on: location.machine };
          const top = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "rev-parse", "--show-toplevel"], options);
          if (top.code !== 0) {
            value = /not a git repository/i.test(top.stderr) ? { kind: "not-repository" } : { kind: "inaccessible" };
          } else {
            const common = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "rev-parse", "--path-format=absolute", "--git-common-dir"], options);
            const root = gitPath(top.stdout), repo = gitPath(common.stdout);
            value = common.code === 0 && root && repo ? { kind: "repo", root, repo } : { kind: "inaccessible" };
          }
        } catch (_error) {
          value = { kind: "inaccessible" };
        }
        // Reconcile live locations and machine state before accepting a reply.
        this.refresh(taskCx);
        this.inFlight--;
        location.pending = false;
        if (this.locations.get(key) === location)
          location.result = { ...value, at: Date.now() };
        this.refresh(taskCx);
        taskCx.notify();
      });
    }
  }

  activate(entry, cx) {
    const currentTerminals = terminals(), currentPanes = panes();
    const action = selectAgentAction(entry.address, currentTerminals, currentPanes);
    if (!action) {
      this.error = `Terminal ${entry.address} is no longer live.`;
      cx.notify();
      return;
    }
    if ((!entry.agent || !entry.status) && action.name === "agent.focus") action.name = "pane.focus";
    this.error = null;
    run(action.name, action.args);
    cx.notify();
  }

  activatePane(pane, cx) {
    const current = panes().find(candidate => candidate.pane === pane.pane && candidate.tab === pane.tab
      && candidate.terminal === pane.terminal && candidate.mod === pane.mod);
    if (!current) {
      this.error = "Pane is no longer available.";
      cx.notify();
      return;
    }
    this.error = null;
    run("pane.focus", { pane: current.pane });
    cx.notify();
  }

  menu(space) {
    openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: space.id } } });
  }

  button(id, text, active, onClick, t) {
    return div().id(id).px(this.compact ? 3 : 6).py(4).rounded(4).text_size(11).cursor_pointer()
      .text_color(active ? t.accent : t.muted).bg(active ? t.raised : t.chrome)
      .hover(s => s.bg(t.hover)).on_click(onClick).child(text);
  }

  isOpen(id, automatic) {
    if (this.mode === "agents" && (this.filter !== "all" || this.search.value().trim())) return !this.transientFolded.has(id);
    return this.opened.has(id) || (automatic && !this.folded.has(id));
  }

  toggleOpen(id, automatic) {
    if (this.mode === "agents" && (this.filter !== "all" || this.search.value().trim())) {
      if (this.transientFolded.has(id)) this.transientFolded.delete(id);
      else this.transientFolded.add(id);
      return;
    }
    if (this.isOpen(id, automatic)) { this.opened.delete(id); this.folded.add(id); }
    else { this.folded.delete(id); this.opened.add(id); }
  }

  badges(entries, t, includeTotal = true, includeWorking = true) {
    const count = agentSummary(entries);
    if (this.compact) return h_flex().flex_none().gap(1).text_size(8)
      .when(count.error > 0, el => el.child(div().text_color(this.statusColors.blocked).tooltip(`${count.error} errors`).child("×")))
      .when(count.blocked > 0, el => el.child(div().text_color(this.statusColors.blocked).tooltip(`${count.blocked} waiting for input`).child("!")))
      .when(count.done > 0, el => el.child(div().text_color(this.statusColors.done).tooltip(`${count.done} unseen results`).child("✓")))
      .when(includeWorking && count.working > 0, el => el.child(div().text_color(this.statusColors.working).tooltip(`${count.working} working`).child("▶")));
    return h_flex().flex_none().gap(5).text_size(10)
      .when(count.error > 0, el => el.child(div().text_color(this.statusColors.blocked).tooltip(`${count.error} errors`).child(`×${count.error}`)))
      .when(count.blocked > 0, el => el.child(div().text_color(this.statusColors.blocked).tooltip(`${count.blocked} waiting for input`).child(`!${count.blocked}`)))
      .when(count.done > 0, el => el.child(div().text_color(this.statusColors.done).tooltip(`${count.done} unseen results`).child(`✓${count.done}`)))
      .when(includeWorking && count.working > 0, el => el.child(div().text_color(this.statusColors.working).tooltip(`${count.working} working`).child(`▶${count.working}`)))
      .when(count.total > 0 && !this.narrow && (includeTotal || !(count.error || count.blocked || count.done || count.working)), el => el.child(div().text_color(t.dim).tooltip(`${count.total} agents`).child(String(count.total))));
  }

  heading(id, text, entries, t, automatic, tooltip, countOnly = false, rootSpace = null, selected = false, rootEntries = entries) {
    const opened = this.isOpen(id, automatic);
    const separateRootStatus = Boolean(rootSpace) && entries.some(entry => entry.space.id !== rootSpace.id);
    const rootCounts = rootSpace ? agentSummary(rootEntries) : null;
    const rootMark = rootCounts && (rootCounts.error ? "×" : rootCounts.blocked ? "!" : rootCounts.done ? "✓" : rootCounts.working ? null : "·");
    const rootBranch = branchName(rootSpace);
    return h_flex().id(`heading-${id}`).h(30).flex_none().items_center().gap(this.compact ? 1 : 5).px(this.compact ? 2 : 6).rounded(4).cursor_pointer()
      .when(!countOnly, el => el.mt(3)).when(selected, el => el.bg(t.selected)).text_size(countOnly ? 11.5 : 12.5).text_color(t.foreground).hover(s => s.bg(t.hover))
      .tooltip([text, tooltip, rootBranch ? `Branch: ${rootBranch}` : null, !countOnly ? summaryText(agentSummary(entries)) : null].filter(Boolean).join(" · "))
      .on_mouse_down("right", () => { if (rootSpace) this.menu(rootSpace); })
      .on_click((_e, cx) => { if (rootSpace) run("space.select", { id: rootSpace.id }); else { this.toggleOpen(id, automatic); cx.notify(); } })
      .child(div().id(`${id}-disclosure`).flex_none().cursor_pointer()
        .on_click((_e, cx) => { cx.stop_propagation(); this.toggleOpen(id, automatic); cx.notify(); })
        .child(icon(opened ? "chevron-down" : "chevron-right").size(this.compact ? 9 : 12).text_color(t.dim)))
      .child(div().id(rootSpace ? `${id}-root-select-${rootSpace.id}` : `${id}-label`).flex_1().min_w(0).truncate().font_medium().when(!countOnly, el => el.font_semibold()).text_color(rootSpace ? workspaceTone(rootEntries, this.statusColors) : t.foreground)
        .when(Boolean(rootSpace), el => el.tooltip([`Open ${rootSpace.name} workspace`, summaryText(agentSummary(rootEntries))].filter(Boolean).join(" · ")).on_click((_e, cx) => { cx.stop_propagation(); run("space.select", { id: rootSpace.id }); }))
        .child(text))
      .when(Boolean(rootBranch) && !this.compact, el => el.child(div().max_w(80).truncate().text_size(10).text_color(t.muted).tooltip(`Branch: ${rootBranch}`).child(rootBranch)))
      .when(separateRootStatus && Boolean(rootMark), el => el.child(div().id(`${id}-root-status`).flex_none().text_color(workspaceTone(rootEntries, this.statusColors))
        .tooltip(`Root workspace: ${summaryText(rootCounts) || "No active status reported"}`).child(rootMark)))
      .child(countOnly ? div().text_size(10).text_color(t.dim).child(String(entries.length))
        : separateRootStatus ? h_flex().pl(this.compact ? 2 : 5).border_l(1).border_color(t.border).child(this.badges(entries, t)) : this.badges(entries, t))
      .when(Boolean(rootSpace), el => el.child(div().id(`${id}-root-menu-${rootSpace.id}`).px(this.compact ? 1 : 4).flex_none().cursor_pointer().text_color(t.muted)
        .on_click((_e, cx) => { cx.stop_propagation(); this.menu(rootSpace); }).child("⋯")));
  }

  projectRow(space, entries, t, prefix, root, target, tab, isRepo, selected, repository = null, branch = null) {
    const name = root ? base(root) : (space.name || "Unknown space");
    const detail = space.name && space.name !== name ? space.name : null;
    const repoLabel = repository && (repository.info.kind === "repo" ? this.compact ? repository.name : `Repo · ${repository.name}` : repository.name);
    const metadata = repository && [repoLabel, repository.machine, detail].filter(Boolean).join(" · ");
    const tooltip = [space.name, root, space.machine, repository?.info.repo, repoLabel, branch ? `Branch: ${branch}` : null, summaryText(agentSummary(entries))].filter(Boolean).join(" · ");
    return h_flex().id(`${prefix}-space-${space.id}`).h(repository ? 42 : 30).flex_none().items_center().gap(this.compact ? 1 : 5).pl(this.compact ? 2 : repository || this.narrow ? 6 : 16).pr(this.compact ? 2 : 5).rounded(4)
      .when(selected, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .cursor_pointer().tooltip(tooltip || name)
      .on_mouse_down("right", () => this.menu(space))
      .on_click((_e, cx) => { if (target) this.activate(target, cx); else if (tab) run("tab.select", { id: tab }); else run("space.select", { id: space.id }); })
      .child(icon(isRepo ? "git-branch" : "folder").size(this.compact ? 9 : 12).text_color(t.dim))
      .child(v_flex().flex_1().min_w(0)
        .child(div().min_w(0).truncate().text_size(12.5).font_medium().text_color(workspaceTone(entries, this.statusColors)).child(name))
        .when(Boolean(repository), el => el.child(h_flex().min_w(0).gap(6).items_center().text_size(this.compact ? 10 : 10.5)
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(metadata))
          .when(Boolean(branch) && !this.compact, line => line.child(div().max_w(90).truncate().text_color(t.muted).tooltip(`Branch: ${branch}`).child(branch))))))
      .when(!repository && Boolean(branch) && !this.compact, el => el.child(div().max_w(90).truncate().text_size(10).text_color(t.muted).tooltip(`Branch: ${branch}`).child(branch)))
      .when(!repository && Boolean(detail) && !this.narrow && !branch, el => el.child(div().max_w(65).truncate().text_size(10).text_color(t.dim).child(detail)))
      .child(this.badges(entries, t, false, false))
      .child(div().id(`${prefix}-menu-${space.id}`).px(this.compact ? 1 : 4).flex_none().cursor_pointer().text_color(t.muted)
        .on_click((_e, cx) => { cx.stop_propagation(); this.menu(space); }).child("⋯"));
  }

  entryRow(entry, t, prefix, showCwd, label, projectIndent = null, actualRoot = null) {
    const status = entry.agent && !entry.status ? "Status unavailable" : statusLabel(entry.status);
    const location = entry.cwd ? base(entry.cwd) : "?";
    const report = currentReport(entry), message = statusMessage(entry);
    const progress = (entry.status === "working" || entry.status === "blocked") && Number.isInteger(report?.progress) && report.progress >= 0 && report.progress <= 100 ? report.progress : null;
    const tooltip = [entry.title, entry.program ? `Program: ${entry.program}` : null, entry.app ? `App: ${entry.app}` : null,
      `Status: ${status}`, message ? `Message: ${message}` : null, entry.cwd ? `Directory: ${entry.cwd}` : null, actualRoot ? `Different checkout: ${actualRoot}` : null,
      entry.branch ? `Branch: ${entry.branch}` : null, entry.parent ? `Parent: ${entry.parent}` : null, `Terminal: ${entry.address}`].filter(Boolean).join(" · ");
    const mark = entry.agent ? ({ working: "●", blocked: "!", done: "✓", idle: "·", error: "×" })[entry.status] ?? "?" : "·";
    const tone = entry.status === "error" ? this.statusColors.blocked : (this.statusColors[entry.status] ?? t[entry.status] ?? t.muted);
    const titleTone = entry.pane?.focused || urgentStatus(entry.status) || entry.status === "working" ? t.foreground : t.muted;
    const program = entry.pane?.program ?? entry.terminal?.program;
    const picture = program?.icon
      ? (program.tint ? svg(program.icon).size(13).flex_none().text_color(t.muted) : image(program.icon).size(13).flex_none())
      : svg("icons/agent.svg").size(13).flex_none().text_color(t.muted);
    const details = [entry.program, showCwd ? location : null, message, entry.address].filter(Boolean).join(" · ");
    if (projectIndent !== null) return h_flex().id(`${prefix}-terminal-${entry.address}`).h(25).flex_none().items_center().gap(this.compact ? 1 : 5)
      .pl(this.compact ? 3 : this.narrow ? 6 : projectIndent).pr(5).rounded(4)
      .when(Boolean(entry.pane?.focused), el => el.bg(t.selected)).cursor_pointer().hover(s => s.bg(t.hover))
      .tooltip(tooltip).on_click((_e, cx) => this.activate(entry, cx))
      .child(div().w(this.compact ? 7 : 10).flex_none().text_color(tone).child(mark))
      .child(picture)
      .child(div().flex_1().min_w(0).truncate().text_color(titleTone).child(`${entry.parent ? "↳ " : ""}${entry.title}`))
      .when(Boolean(actualRoot) && !this.narrow, el => el.child(div().max_w(65).truncate().text_size(10).text_color(t.dim).child(`↗${base(actualRoot)}`)))
      .when(progress !== null && !this.narrow, el => el.child(div().flex_none().text_size(10).text_color(tone).child(`${progress}%`)));
    return h_flex().id(`${prefix}-terminal-${entry.address}`).flex_none().items_start().gap(6).pl(this.narrow ? 6 : 14).pr(6).py(4)
      .rounded(4).when(Boolean(entry.pane?.focused), el => el.bg(t.selected)).cursor_pointer().hover(s => s.bg(t.hover))
      .tooltip(tooltip)
      .on_click((_e, cx) => this.activate(entry, cx))
      .child(div().w(10).flex_none().text_color(tone).child(mark))
      .child(picture)
      .child(v_flex().flex_1().min_w(0).gap(1)
        .child(div().min_w(0).truncate().text_color(titleTone).child(`${entry.parent ? "↳ " : ""}${label}`))
        .child(h_flex().min_w(0).items_center().gap(5).text_size(10)
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(details))
          .when(progress !== null, el => el.child(div().flex_none().text_color(tone).child(`${progress}%`)))));
  }

  paneRow(pane, t, prefix, indent) {
    const name = pane.title || pane.program?.name || pane.mod || (pane.terminal ? "Terminal" : "Mod pane");
    const program = pane.program;
    const picture = program?.icon
      ? (program.tint ? svg(program.icon).size(13).flex_none().text_color(t.muted) : image(program.icon).size(13).flex_none())
      : icon(pane.terminal ? "terminal" : "layers").size(13).text_color(t.muted);
    const tooltip = [name, pane.mod ? `Mod: ${pane.mod}` : null, program?.name ? `Program: ${program.name}` : null,
      pane.cwd ? `Directory: ${pane.cwd}` : null, pane.branch ? `Branch: ${pane.branch}` : null,
      pane.terminal ? `Terminal: ${pane.terminal}` : null, `Pane: ${pane.pane}`].filter(Boolean).join(" · ");
    return h_flex().id(`${prefix}-pane-${pane.pane}`).h(25).flex_none().items_center().gap(this.compact ? 1 : 5)
      .pl(this.compact ? 3 : this.narrow ? 6 : indent).pr(5).rounded(4)
      .when(Boolean(pane.focused), el => el.bg(t.selected)).cursor_pointer().hover(el => el.bg(t.hover))
      .tooltip(tooltip).on_click((_e, cx) => this.activatePane(pane, cx))
      .child(div().w(this.compact ? 7 : 10).flex_none().text_color(t.dim).child("·"))
      .child(picture)
      .child(div().flex_1().min_w(0).truncate().text_color(pane.focused ? t.foreground : t.muted).child(name));
  }

  render(cx) {
    if (this.picker) return this.picker.render(cx);
    const t = theme();
    this.statusColors = statusPalette(t);
    const groupByRepository = shared(GROUP_REPOSITORIES) !== false;
    const allSpaces = spaces(), allPanes = panes(), allTerminals = terminals(), allAgents = agents(), allMachines = machines();
    const entries = workspaceEntries(allSpaces, allPanes, allAgents, allTerminals);
    const workspaceCwds = workspaceLocations(allSpaces, allPanes, allTerminals, allAgents);
    const query = this.mode === "agents" ? this.search.value().trim().toLowerCase() : "";
    const matches = (...values) => !query || values.some(v => String(v ?? "").toLowerCase().includes(query));
    const allowed = entry => this.filter === "all" || (entry.agent && (entry.status === this.filter || (this.filter === "attention" && (urgentStatus(entry.status) || entry.status === "done"))));
    const machineState = machine => allMachines.find(m => m.name === machineKey(machine))?.layout ?? "unavailable";
    // Model changes can arrive between periodic refreshes and process replies.
    // Retire those records immediately so an old reply cannot revive them.
    const activeLocations = new Set();
    for (const entry of entries) if (machineState(entry.space.machine) === "ready") {
      for (const cwd of [entry.cwd, workspaceCwds.get(entry.space.id)]) {
        if (typeof cwd === "string" && cwd) activeLocations.add(locationKey(entry.space.machine, cwd));
      }
    }
    for (const key of this.locations.keys()) if (!activeLocations.has(key)) this.locations.delete(key);
    const infoAt = (machine, cwd) => {
      if (machineState(machine) !== "ready") return { kind: "offline" };
      if (!cwd) return { kind: "unknown" };
      const location = this.locations.get(locationKey(machine, cwd));
      return location?.result ?? { kind: "loading" };
    };
    const infoFor = entry => infoAt(entry.space.machine, entry.cwd);
    const projectCwd = entry => workspaceCwds.get(entry.space.id) ?? null;
    const projectInfoFor = entry => infoAt(entry.space.machine, projectCwd(entry));
    const directoriesBySpace = new Map(), entriesByLocation = new Map(), focusedSpaces = new Set();
    for (const entry of entries) {
      if (entry.pane?.focused) focusedSpaces.add(entry.space.id);
      const path = projectInfoFor(entry).root ?? projectCwd(entry) ?? null;
      if (!directoriesBySpace.has(entry.space.id)) directoriesBySpace.set(entry.space.id, new Set());
      directoriesBySpace.get(entry.space.id).add(entry.cwd ?? null);
      const key = JSON.stringify([entry.space.id, path]);
      if (!entriesByLocation.has(key)) entriesByLocation.set(key, []);
      entriesByLocation.get(key).push(entry);
    }
    const rows = [];
    const order = [], ordered = new Set();
    const remember = entry => {
      if (entry.agent && !ordered.has(entry.address)) { ordered.add(entry.address); order.push(entry.address); }
    };
    if (this.mode === "agents") {
      const visible = entries.filter(entry => {
        if (!entry.agent || !allowed(entry)) return false;
        const location = infoFor(entry), worktree = location.root ? base(location.root) : (entry.space.name || (entry.cwd ? base(entry.cwd) : "Unknown worktree"));
        return matches(projectLabel(location), worktree, entry.space.machine, entry.space.name, entry.title, entry.program, entry.app, statusMessage(entry), entry.status, statusLabel(entry.status), entry.address, entry.cwd, entry.branch, location.repo, location.root);
      });
      const groups = [
        ["blocked", "Needs you", entry => entry.status === "blocked"],
        ["error", "Error", entry => entry.status === "error"],
        ["done", "Done", entry => entry.status === "done"],
        ["working", "Working", entry => entry.status === "working"],
        ["idle", "Idle", entry => entry.status === "idle"],
        ["unavailable", "Status unavailable", entry => !entry.status],
        ["other", "Other", entry => Boolean(entry.status) && !["blocked", "error", "done", "working", "idle"].includes(entry.status)],
      ];
      for (const [key, label, belongs] of groups) {
        const members = visible.filter(belongs);
        if (!members.length) continue;
        const id = `agent-status-${key}`, open = this.isOpen(id, true);
        rows.push(this.heading(id, label, members, t, true, null, true));
        for (const entry of members) {
          remember(entry);
          if (!open) continue;
          const location = infoFor(entry), project = location.kind === "repo" ? projectLabel(location) : null;
          const worktree = location.root ? base(location.root) : (entry.space.name || (entry.cwd ? base(entry.cwd) : "Unknown worktree"));
          const name = project && project !== worktree ? `${project} · ${worktree}` : worktree;
          const display = entry.space.machine ? `${entry.space.machine} · ${name}` : name;
          rows.push(this.entryRow(entry, t, "agents", (directoriesBySpace.get(entry.space.id)?.size ?? 0) > 1, display));
        }
      }
    } else {
      const tabSpaces = new Map(allSpaces.flatMap(space => space.tabs.map(tab => [tab.id, space.id])));
      const panesBySpace = new Map();
      for (const pane of allPanes) {
        const space = tabSpaces.get(pane.tab);
        if (!space || !pane.pane) continue;
        if (!panesBySpace.has(space)) panesBySpace.set(space, []);
        panesBySpace.get(space).push(pane);
      }
      const spaceOrder = new Map();
      for (const entry of entries) if (!spaceOrder.has(entry.space.id)) spaceOrder.set(entry.space.id, spaceOrder.size);
      const projectRows = groupProjects(entries, projectInfoFor).map(group => {
        const { key, machine, info, entries: visible } = group;
        const bySpace = new Map();
        for (const entry of visible) {
          const root = projectInfoFor(entry).root ?? projectCwd(entry) ?? null;
          const spaceKey = JSON.stringify([entry.space.id, root]);
          if (!bySpace.has(spaceKey)) bySpace.set(spaceKey, { root, entries: [], order: spaceOrder.get(entry.space.id) });
          bySpace.get(spaceKey).entries.push(entry);
        }
        const workspaces = [...bySpace.values()].map(item => ({ ...item, priority: groupPriority(item.entries) }));
        return { key, machine, info, name: projectLabel(info), visible, workspaces, priority: groupPriority(visible) };
      }).filter(group => group.visible.length);
      const addWorkspace = (group, item, shown, merged, flat) => {
        const { root, entries: list } = item, space = list[0].space;
        const atLocation = (entriesByLocation.get(JSON.stringify([space.id, root])) ?? []).filter(entry => entry.address);
        const workspacePanes = panesBySpace.get(space.id) ?? [];
        const target = atLocation.length === 1 && workspacePanes.length === 1 && atLocation[0].pane?.pane === workspacePanes[0].pane ? atLocation[0] : null;
        const tabs = new Set([...workspacePanes.map(pane => pane.tab), ...atLocation.map(entry => entry.pane?.tab)].filter(Boolean));
        const tab = tabs.size === 1 && atLocation.every(entry => entry.pane?.tab) ? tabs.values().next().value : null;
        const selected = space.active && (!focusedSpaces.has(space.id) || atLocation.some(entry => entry.pane?.focused));
        const prefix = `project-${group.key}-${JSON.stringify(root)}`;
        if (shown && !merged) rows.push(this.projectRow(space, list, t, prefix, root, target, tab, group.info.kind === "repo", selected, flat ? group : null, machineState(space.machine) === "ready" ? branchName(space) : null));
        if (shown) {
          const agentsByPane = new Map(list.filter(entry => entry.agent && entry.pane?.pane).map(entry => [entry.pane.pane, entry]));
          const displayed = new Set();
          const addAgent = entry => {
            const actual = infoFor(entry), workspace = projectInfoFor(entry);
            const differentRoot = workspace.kind === "repo" && actual.kind === "repo" && actual.root !== workspace.root ? actual.root : null;
            rows.push(this.entryRow(entry, t, prefix, false, entry.title, flat || merged ? 17 : 32, differentRoot));
            displayed.add(entry);
          };
          for (const pane of workspacePanes) {
            const entry = agentsByPane.get(pane.pane);
            if (entry) addAgent(entry);
            else rows.push(this.paneRow(pane, t, prefix, flat || merged ? 17 : 32));
          }
          for (const entry of list) if (entry.agent && !displayed.has(entry)) addAgent(entry);
        }
        for (const entry of list) remember(entry);
      };
      if (groupByRepository) {
        projectRows.sort((a, b) => a.priority - b.priority);
        for (const group of projectRows) {
          const { key, machine, info, name, visible, workspaces } = group;
          const id = `project-${key}`, automatic = info.kind !== "loading", projectOpen = this.isOpen(id, automatic);
          const repoRoot = info.kind === "repo" && info.repo.endsWith("/.git") ? info.repo.slice(0, -5) : null;
          const rootSpaces = repoRoot ? workspaces.filter(item => item.root === repoRoot) : [];
          const rootCandidate = rootSpaces.length === 1 && rootSpaces[0].entries[0].space.name === name ? rootSpaces[0] : null;
          workspaces.sort((a, b) => a.priority - b.priority);
          const merged = workspaces[0] === rootCandidate ? rootCandidate : null;
          const rootSpace = merged?.entries[0].space ?? null;
          const rootSelected = rootSpace?.active && (!focusedSpaces.has(rootSpace.id) || merged.entries.some(entry => entry.pane?.focused));
          rows.push(this.heading(id, machine ? `${machine} · ${name}` : name, visible, t, automatic, info.repo, false, rootSpace, rootSelected, merged?.entries));
          for (const item of workspaces) addWorkspace(group, item, projectOpen, item === merged, false);
        }
      } else {
        const workspaces = projectRows.flatMap(group => group.workspaces.map(item => ({ group, item })));
        workspaces.sort((a, b) => a.item.priority - b.item.priority || a.item.order - b.item.order);
        const sections = [
          ["attention", "Needs attention", this.statusColors.blocked],
          ["done", "Done", this.statusColors.done],
          ["working", "Working", this.statusColors.working],
          ["other", "Other", t.muted],
        ];
        let previous = -1;
        for (const { group, item } of workspaces) {
          if (item.priority !== previous) {
            const [key, label, color] = sections[item.priority];
            rows.push(div().id(`flat-status-${key}`).role("heading").mt(5).px(6).py(4).text_size(11).font_medium().text_color(color).truncate().tooltip(label).child(label));
            previous = item.priority;
          }
          addWorkspace(group, item, true, false, true);
        }
      }
      for (const machine of allMachines) if (machine.layout !== "ready") {
        rows.push(div().px(6).py(4).text_size(11).text_color(t.muted).child(`${machine.name ?? "This computer"}: ${machine.layout === "loading" ? "loading" : "unavailable"}`));
      }
    }
    for (const entry of entries) if (entry.agent && !ordered.has(entry.address)) {
      ordered.add(entry.address); order.push(entry.address);
    }
    setAgentOrder(order);
    const sidebar = layout()?.children?.find(node => node.id === "sidebar");
    const macRail = window()?.platform === "macos" && typeof sidebar?.size?.px === "number" && sidebar.size.px < 160;
    const groupingButton = (grouped, label) => this.button(`navigator-group-${grouped ? "grouped" : "flat"}`, this.narrow ? label[0] : label, groupByRepository === grouped, (_e, cx) => {
      if (groupByRepository !== grouped) { setShared(GROUP_REPOSITORIES, grouped); cx.notify(); }
    }, t).role("button").accessibility_label(`${label} view${groupByRepository === grouped ? ", selected" : ""}`)
      .tooltip(grouped ? "Group workspaces by repository" : "Group workspaces by agent status");
    return v_flex().id("workbench-navigator").size_full().min_h(0).min_w(0).bg(t.chrome).text_color(t.foreground).text_size(12)
      .on_size_change((size, cx) => {
        // Logical pixels still include Herdr's UI zoom. Normalize so controls
        // switch at the same available width relative to their text.
        const zoom = settings().zoom;
        const width = size.width / (typeof zoom === "number" && zoom > 0 ? zoom : 1);
        const narrow = width < 220, compact = width < 140;
        if (narrow !== this.narrow || compact !== this.compact) { this.narrow = narrow; this.compact = compact; cx.notify(); }
      })
      .child(h_flex().flex_none().flex_wrap().items_center().px(5).py(5).gap(3)
        .when(macRail, el => el.child(this.button("navigator-expand", "»", false, () => {
          const width = shared("sidebar.width");
          setShared("sidebar.collapsed", false);
          run("layout.resize", { id: "sidebar", px: typeof width === "number" && width >= 160 ? width : 268 });
        }, t).tooltip("Expand sidebar")))
        .child(this.button("navigator-projects", this.compact ? "P" : "Projects", this.mode === "projects", (_e, cx) => { this.mode = "projects"; cx.notify(); }, t).tooltip("Projects"))
        .child(this.button("navigator-agents", this.compact ? "A" : "Agents", this.mode === "agents", (_e, cx) => { this.mode = "agents"; cx.notify(); }, t).tooltip("Agents"))
        .child(div().flex_1().min_w(0))
        .when(this.mode === "projects", el => el.child(h_flex().id("navigator-grouping").flex_none().items_center().rounded(5).border_1().border_color(t.border).p(1)
          .child(groupingButton(false, "Flat")).child(groupingButton(true, "Grouped"))))
        .child(div().id("navigator-github").size(26).flex_none().flex().items_center().justify_center().rounded(6)
          .cursor_pointer().text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground)).tooltip("GitHub")
          .on_click(() => run("mod.open", { name: "workbench-github" })).child(svg("icons/gh.svg").size(14)))
        .child(this.button("navigator-new", "+", false, () => run("space.new"), t).tooltip("New space")))
      .when(this.mode === "agents", el => el
        .child(div().flex_none().px(5).py(5).child(Input.new(this.search).h(27).px(6).rounded(5).border_1().border_color(t.input).bg(t.background).text_size(12).text_color(t.foreground)))
        .child(h_flex().flex_none().flex_wrap().px(5).pb(4).gap(2)
          .children([["all", "All", "A"], ["attention", "Attention", "!"], ["blocked", "Blocked", "B"], ["done", "Done", "✓"]].map(([id, label, short]) => this.button(`navigator-filter-${id}`, this.compact ? short : label, this.filter === id, (_e, cx) => { this.transientFolded.clear(); this.filter = id; cx.notify(); }, t).tooltip(label)))))
      .when(Boolean(this.error), el => el.child(div().px(6).py(4).text_color(t.blocked ?? t.foreground).child(this.error)))
      .child(v_flex().id("navigator-scroll").flex_1().min_h(0).px(4).pb(10).overflow_y_scrollbar().mode("always")
        .children(rows.length ? rows : [div().px(6).py(8).text_color(t.muted).child(this.mode === "agents" ? "No matching agents." : "No matching projects. Use + to create a space.")]));
  }
}
