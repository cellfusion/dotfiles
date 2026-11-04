// Personal copy of Spaces: keep machine/worktree navigation and show agents
// beneath their owning space, with attention counts even while folded.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { spaces, machines, panes, agents, terminals, setAgentOrder, run, openOverlay, exec, hc, theme, shared, setShared, watchFolder, window, layout } from "herdr";
import { buildGroups } from "./views.js";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// Where a space is now: its first terminal's live folder, else where it was made.
// `ps`: panes(), read once by the caller (each read copies every pane).
function place(s, ps) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}
const rowHeight = ({ tree }) => (tree ? 28 : 30);
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);
const base = (path) => path.replace(/\/+$/, "").split("/").pop();
// Changes made outside Herdr (an editor's save, a commit in another app): looked
// for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };

// A space speaks up only when something in it needs you.
export function glyph(status) {
  return status === "blocked" || status === "done" ? "●" : "·";
}

export function tone(t, status) {
  return t[status] ?? t.unknown;
}

export default class Spaces extends View {
  init(_props, cx) {
    this.git = {}; // where() -> { name, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.folded = new Set(JSON.parse(localStorage.getItem("machines.folded") ?? "[]"));
    this.spaceFolded = new Set(JSON.parse(localStorage.getItem("spaces.folded") ?? "[]"));
    this.tags = JSON.parse(localStorage.getItem("space.tags") ?? "{}");
    this.views = JSON.parse(localStorage.getItem("space.views") ?? "[]");
    this.view = { query: "", tag: "", status: "", group: "none", ...JSON.parse(localStorage.getItem("space.view") ?? "{}") };
    this.panel = null;
    this.editingTags = null;
    this.searchInput = InputState.new({ value: this.view.query, placeholder: "Search spaces or tags" });
    this.searchInput.on("change", (_e, cx) => { this.setView({ query: this.searchInput.value() }); cx.notify(); });
    this.tagsInput = InputState.new({ placeholder: "Tags, separated by commas" });
    this.tagsInput.on("submit", (_e, cx) => { this.saveTags(); cx.notify(); });
    this.viewInput = InputState.new({ placeholder: "View name" });
    this.viewInput.on("submit", (_e, cx) => { this.saveView(); cx.notify(); });
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx) {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.due(now, sp, panes());
    if (due.size) this.refreshGit(due, cx);
    if (sp.some((s) => !this.shown.has(s.id))) cx.notify();
  }

  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those on
  // a machine that is back, and repos in view whose fallback is due.
  due(now, sp, ps) {
    // Moved there: what it knew of that place may be old.
    const at = {};
    for (const s of sp) at[s.id] = where(s, ps);
    const keys = new Set(Object.values(at).filter((k) => JSON.parse(k)[1]));
    const due = new Set([...keys].filter((k) => !(k in this.git)));
    for (const [id, k] of Object.entries(at)) if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] = p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      if (ready && this.ready[m.name] === false) for (const k of keys) if (JSON.parse(k)[0] === m.name) due.add(k);
      this.ready[m.name] = ready;
    }
    if (window().active) {
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (asks && !this.folded.has(JSON.parse(k)[0]) && now - (this.checked[k] ?? 0) > FALLBACK) due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their ahead/behind).
  sameRepo(key, keys) {
    const repo = this.git[key]?.repo;
    return [key, ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : [])];
  }

  refreshMachines(cx) {
    cx.spawn(async cx => {
      try { const r = await hc(["machine", "ls", "--json"]); if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary); } catch {}
      cx.notify();
    });
  }

  // One look at a time, each place once however often it was asked for meanwhile.
  refreshGit(keys, cx) {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(Object.values(this.git).filter(Boolean).map((g) => JSON.parse(g.repo)).filter(([on]) => !on).map(([, repo]) => repo));
      for (const repo of this.watching) if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One place's git: branch, ahead/behind, its repo.
  async check(key, cx) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      // No optional locks: a status that touched the index would wake the watch again.
      // Writes nothing under .git (index lock, fsmonitor cookie): watch() would wake on it.
      const r = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch"], { cwd, on });
      if (r.code !== 0) {
        // Only git's own "no" is remembered as no repo; anything else is asked again.
        if (!/not a git repository/i.test(r.stderr)) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      // The repo's own .git folder names it; a worktree's top differs from it.
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on });
      const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
      const repo = common.stdout.trim();
      const name = repo.endsWith("/.git") ? base(repo.slice(0, -5)) : base(repo).replace(/\.git$/, "");
      const info = { name, branch: null, ahead: 0, behind: 0, repo: JSON.stringify([on, repo]), linked: repo !== `${top.stdout.trim()}/.git` };
      for (const line of r.stdout.split("\n")) {
        if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
        else if (line.startsWith("# branch.ab ")) {
          const [a, b] = line.slice(12).split(" ");
          info.ahead = Math.abs(parseInt(a, 10)) || 0;
          info.behind = Math.abs(parseInt(b, 10)) || 0;
        }
      }
      this.git[key] = info;
      if (!on) this.watch(repo, cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  watch(repo, cx) {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(repo);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo)) this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === mine), cx);
        }
      } catch { this.watching.delete(repo); }
    });
  }

  menu(w) {
    // A popup is as tall as its items; height is only the most.
    openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: w.id } } });
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered() {
    const sp = spaces(), ps = panes();
    const ready = (w) => this.shown.has(w.id) || where(w, ps) in this.git || Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp) if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp.map((w, i) => ({ w, i, g: this.git[where(w, ps)] ?? null })).filter((r) => this.shown.has(r.w.id));
    const mains = new Set(list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo));
    const nested = (r) => r.g?.linked && mains.has(r.g.repo);
    const out = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) => out.push({ ...k, parent: r.w.id, tree: n === kids.length - 1 ? "└─" : "├─" }));
    }
    return out;
  }

  visibleGroups(rows = this.ordered()) {
    const groups = buildGroups(rows, this.tags, this.view, w => this.statusesOf(w));
    if (this.view.group !== "none") return groups;
    const ids = new Set(groups[0].rows.map(r => r.w.id));
    groups[0].rows = groups[0].rows.filter(r => !r.parent || !ids.has(r.parent) || !this.spaceFolded.has(r.parent));
    return groups;
  }

  setView(change) {
    this.view = { ...this.view, ...change };
    localStorage.setItem("space.view", JSON.stringify(this.view));
  }

  saveTags() {
    if (!this.editingTags) return;
    const values = [...new Set(this.tagsInput.value().split(",").map(x => x.trim()).filter(Boolean))];
    if (values.length) this.tags[this.editingTags] = values;
    else delete this.tags[this.editingTags];
    localStorage.setItem("space.tags", JSON.stringify(this.tags));
    this.editingTags = null;
    this.panel = null;
  }

  saveView() {
    const name = this.viewInput.value().trim();
    if (!name) return;
    const entry = { name, view: { ...this.view } };
    const i = this.views.findIndex(v => v.name === name);
    if (i < 0) this.views.push(entry);
    else this.views[i] = entry;
    localStorage.setItem("space.views", JSON.stringify(this.views));
    this.viewInput.set_value("");
  }

  statusesOf(w) {
    const statuses = [];
    const visit = a => {
      const status = a.status === "error" ? "blocked" : a.status;
      if (["blocked", "done", "working", "idle"].includes(status)) statuses.push(status);
      for (const k of this.childrenByParent.get(a.address) ?? []) {
        if (!this.listed.has(k.address)) visit({ ...k, status: k.status === "done" ? "idle" : k.status });
      }
    };
    for (const a of this.bySpace.get(w.id) ?? []) visit(a);
    return statuses;
  }

  controls(t) {
    const button = (id, label, action, active = false) => div().id(id).px(6).py(4).rounded(5).text_size(11)
      .text_color(active ? t.accent : t.foreground).bg(t.raised).cursor_pointer().hover(s => s.bg(t.hover)).on_click(action).child(label);
    const input = state => Input.new(state).h(27).px(6).rounded(5).border_1().border_color(t.input)
      .bg(t.background).text_size(12).text_color(t.foreground);
    const label = text => div().pt(3).text_size(11).text_color(t.dim).child(text);
    const panel = v_flex().id("space-filter-controls").flex_none().max_h(300).overflow_y_scrollbar().px(8).pb(8).gap(5);
    if (this.panel === "filters") {
      const tags = [...new Set(Object.values(this.tags).flat())].sort((a, b) => a.localeCompare(b));
      const statuses = [["", "All"], ["blocked", "Needs you"], ["done", "Done"], ["working", "Working"], ["idle", "Idle"], ["none", "No agent"]];
      return panel.child(label("Filter spaces")).child(input(this.searchInput))
        .child(label("Tag"))
        .child(h_flex().flex_wrap().gap(4)
          .children(["", ...tags].map((tag, i) => button(`filter-tag-${i}`, tag || "All", (_e, cx) => {
            this.setView({ tag }); cx.notify();
          }, this.view.tag === tag))))
        .child(label("Agent state"))
        .child(h_flex().flex_wrap().gap(4)
          .children(statuses.map(([status, name], i) => button(`filter-status-${i}`, name, (_e, cx) => {
            this.setView({ status }); cx.notify();
          }, this.view.status === status))))
        .child(button("filter-clear", "Clear filters", (_e, cx) => {
          this.setView({ query: "", tag: "", status: "" });
          this.searchInput.set_value(""); cx.notify();
        }));
    }
    if (this.panel === "groups") {
      return panel.child(label("Group spaces by"))
        .child(h_flex().flex_wrap().gap(4)
          .children([["none", "Space"], ["tag", "Tag"], ["status", "Agent state"]].map(([value, name]) =>
            button(`group-${value}`, name, (_e, cx) => {
              this.setView({ group: value }); cx.notify();
            }, this.view.group === value))))
        .child(div().text_size(10).text_color(t.dim).child("Agent state uses the most urgent state in each space."));
    }
    if (this.panel === "tags" && this.editingTags) {
      return panel.child(label(`Tags: ${spaces().find(s => s.id === this.editingTags)?.name ?? this.editingTags}`))
        .child(input(this.tagsInput))
        .child(h_flex().gap(4)
          .child(button("tags-save", "Save tags", (_e, cx) => { this.saveTags(); cx.notify(); }))
          .child(button("tags-cancel", "Cancel", (_e, cx) => { this.editingTags = null; this.panel = null; cx.notify(); })));
    }
    if (this.panel === "views") {
      return panel.child(label("Saved views · filters and grouping"))
        .child(h_flex().gap(4).items_center()
          .child(div().flex_1().min_w(0).child(input(this.viewInput)))
          .child(button("view-save", "Save view", (_e, cx) => { this.saveView(); cx.notify(); })))
        .children(this.views.map((entry, i) => h_flex().gap(4).items_center()
          .child(div().flex_1().min_w(0).child(button(`view-${i}`, entry.name, (_e, cx) => {
            this.setView(entry.view);
            this.searchInput.set_value(this.view.query);
            cx.notify();
          })))
          .child(button(`view-delete-${i}`, "×", (_e, cx) => {
            this.views.splice(i, 1);
            localStorage.setItem("space.views", JSON.stringify(this.views)); cx.notify();
          }))));
    }
    return panel;
  }

  // The rows, under a header per machine once one isn't this computer.
  grouped(t, collapsed) {
    const allRows = this.ordered();
    const groups = this.visibleGroups(allRows);
    const rows = this.view.group === "none" ? groups[0].rows : groups.flatMap(g => g.rows);
    const draw = (r, prefix = "") => collapsed ? this.compact(r, t, prefix) : v_flex().flex_none()
      .child(this.row(r, t, prefix))
      .when(Boolean(this.tags[r.w.id]?.length), el => el.child(div().pl(r.tree ? 48 : 26).pr(8).text_size(10).text_color(t.dim)
        .truncate().child(this.tags[r.w.id].map(tag => `#${tag}`).join(" "))))
      .when(!this.spaceFolded.has(r.w.id), el => el.children(
        (this.bySpace.get(r.w.id) ?? []).map(a => this.agentRow(a, t, r.tree ? 48 : 26, prefix))));
    const noMatches = () => div().h(28).px(8).text_size(11).text_color(t.dim).child("No matching spaces");
    if (this.view.group !== "none") {
      const labels = { blocked: "Needs you", done: "Done", working: "Working", idle: "Idle", none: "No agent" };
      return groups.length ? groups.flatMap((group, n) => [
        div().id(`group-${n}`).h(25).px(8).text_size(11).text_color(t.dim)
          .child(this.view.group === "status" ? labels[group.key] : group.key ?? "Untagged"),
        ...group.rows.map(r => draw({ ...r, tree: null }, `group-${n}-`)),
      ]) : [noMatches()];
    }
    const remote = [...new Set([...rows.map(r => r.w.machine).filter(Boolean), ...this.machines.map(m => m.name)])].sort();
    const loading = m => {
      const layout = machines().find(k => k.name === m)?.layout;
      return layout === "loading" || (!layout && this.machines.some(k => k.name === m && k.state === "connected"))
        || spaces().some(s => (s.machine ?? null) === m && !this.shown.has(s.id));
    };
    const loadingRow = m => div().id(`machine-loading-${m ?? "local"}`).h(28).flex_none().px(8).text_size(12).text_color(t.dim).child(collapsed ? "…" : "Loading…");
    if (!remote.length) return loading(null) && !allRows.length ? [loadingRow(null)] : rows.length ? rows.map(r => draw(r)) : [noMatches()];
    const machineNames = [null, ...remote];
    return machineNames.flatMap((m) => {
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const machine = this.machines.find(k => k.name === m);
      const connected = !m || machine?.state === "connected";
      const folded = this.folded.has(m);
      const head = h_flex().id(`machine-${m ?? "local"}`).h(26).flex_none().px(collapsed ? 2 : 8).gap(7).items_center().text_size(11).text_color(t.dim)
        .cursor_pointer().hover(s => s.bg(t.hover))
        .on_click((_e, cx) => {
          folded ? this.folded.delete(m) : this.folded.add(m);
          localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(13).flex_none())
        .when(!collapsed, el => el.child(div().flex_1().truncate().child(m ?? "This computer"))
          .when(!connected, el => el.child(div().flex_none().child((machine?.state ?? "asleep").replace(/_/g, " "))))
          .when(connected, el => el.child(div().id(`machine-add-${m ?? "local"}`).flex_none().px(4).rounded(4).hover(s => s.bg(t.hover).text_color(t.foreground))
            .on_click((_e, cx) => { cx.stop_propagation(); run("space.new", m ? { machine: m } : {}); }).child("+")))
          .child(div().size(6).rounded(3).flex_none().bg(connected ? t.ansi2 : t.dim))
          .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none()));
      const empty = h_flex().id(`machine-new-${m ?? "local"}`).h(28).flex_none().px(8).gap(7).items_center().rounded(7)
        .text_size(12).text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => run("space.new", m ? { machine: m } : {}))
        .child(svg("mods/workspace-chrome/plus.svg").size(12)).when(!collapsed, el => el.child("New space there"));
      return [head, ...(folded ? [] : mine.length ? mine.map(r => draw(r)) : [loading(m) ? loadingRow(m) : allRows.some(r => (r.w.machine ?? null) === m) ? noMatches() : empty])];
    });
  }

  agentRow(a, t, indent, prefix = "") {
    return v_flex().flex_none()
      .child(h_flex().id(`${prefix}agent-${a.address}`).h(27).pl(indent).pr(8).gap(7)
        .items_center().rounded(6).cursor_pointer()
        .when(a.focused, el => el.bg(t.raised))
        .hover(el => el.bg(t.hover))
        .on_click(() => run("agent.focus", { terminal: a.address }))
        .child(div().size(6).flex_none().rounded(3).bg(t[a.status] ?? t.dim))
        .child(div().flex_1().truncate().text_size(12).text_color(t.muted)
          .child(a.tab_name ? `${a.tab_name} · ${a.program?.name ?? a.app ?? a.address}` : a.name || a.program?.name || a.address))
        .child(div().flex_none().text_size(10).text_color(t[a.status] ?? t.dim)
          .child(({blocked: "Needs you", done: "Done", working: "Working", idle: "Idle"})[a.status] ?? a.status ?? "")))
      .children((this.childrenByParent.get(a.address) ?? [])
        .filter(k => !this.listed.has(k.address))
        .map(k => this.agentRow({ ...k, status: k.status === "error" ? "blocked" : k.status === "done" ? "idle" : k.status }, t, indent + 14, prefix)));
  }

  summary(w, t, prefix = "") {
    const counts = {};
    const visit = a => {
      const s = a.status === "error" ? "blocked" : a.status;
      counts[s] = (counts[s] ?? 0) + 1;
      for (const k of this.childrenByParent.get(a.address) ?? []) if (!this.listed.has(k.address)) visit(k);
    };
    for (const a of this.bySpace.get(w.id) ?? []) visit(a);
    return h_flex().gap(4).flex_none()
      .children(["blocked", "done", "working"].filter(s => counts[s]).map(s =>
        div().text_size(10).text_color(t[s]).child(`${s === "blocked" ? "!" : s === "done" ? "●" : "›"}${counts[s]}`)))
      .child(div().id(`${prefix}fold-${w.id}`).px(4).cursor_pointer()
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_mouse_up("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => {
          cx.stop_propagation();
          this.spaceFolded.has(w.id) ? this.spaceFolded.delete(w.id) : this.spaceFolded.add(w.id);
          localStorage.setItem("spaces.folded", JSON.stringify([...this.spaceFolded]));
          cx.notify();
        }).text_color(t.dim).child(this.spaceFolded.has(w.id) ? "›" : "⌄"));
  }

  // Only what's unusual, after the name: "herdr \u00b7 spike \u21912 \u21931". The repo or
  // branch goes when the name already says it (a worktree is named after its branch),
  // and master/main go: nearly every space is on one.
  gitTail(g, tree, name, t) {
    const raw = g.branch ?? "detached";
    const same = (a) => a.toLowerCase() === name.toLowerCase();
    const branch = same(raw) || raw === "master" || raw === "main" ? "" : raw;
    const repo = tree || same(g.name) ? "" : g.name;
    const where = [repo, branch].filter(Boolean).join(" \u00b7 ");
    return h_flex()
      .flex_1()
      .min_w(0)
      .gap(5)
      .justify_end()
      .items_center()
      .text_size(11.5)
      .text_color(t.dim)
      .when(Boolean(where), (el) => el.child(div().min_w(0).truncate().child(where)))
      .when(g.ahead > 0, (el) => el.child(div().flex_none().text_color(t.ansi2).child(`\u2191${g.ahead}`)))
      .when(g.behind > 0, (el) => el.child(div().flex_none().text_color(t.ansi1).child(`\u2193${g.behind}`)));
  }

  row({ w, i, g, tree }, t, prefix = "") {
    const on = w.active;
    const colors = shared("space.colors") ?? {};
    const color = colors[w.id] ?? "ansi6";
    const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    return v_flex()
      .relative()
      .id(`${prefix}space-${w.id}`)
      .px(8)
      .h(rowHeight({ tree }))
      .flex_none()
      .justify_center()
      .rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .when(this.pressed === i && this.over !== i, (el) => el.opacity(0.5))
      .when(this.pressed !== null && this.over === i && this.pressed !== i, (el) => el.child(
        div().absolute().left(0).right(0).h(2).bg(t.accent)
          .when(this.pressed < i, line => line.bottom(0))
          .when(this.pressed > i, line => line.top(0)),
      ))
      .on_mouse_down("left", () => {
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces()[this.pressed];
        const over = source && (source.machine ?? null) === (w.machine ?? null) ? i : null;
        if (this.pressed !== null && this.over !== over) {
          this.over = over;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.pressed = null;
        this.over = null;
        if (this.view.group === "none" && from !== null && over === i && from !== i) run("space.move", { id: spaces()[from].id, index: i + 1 });
        else if (from === i) run("space.select", { id: w.id });
        cx.notify();
      })
      .on_mouse_down("right", () => this.menu(w))
      .child(
        h_flex()
          .gap(9)
          .items_center()
          .when(Boolean(tree), el => el.pl(22).child(svg("mods/workspace-chrome/branch.svg").size(13).text_color(t.dim)))
          .when(!tree, el => el.child(h_flex().size(18).flex_none().rounded(5).bg(fill).items_center().justify_center().text_size(10.5).font_bold().text_color("#ffffff").child([...w.name][0]?.toUpperCase() ?? "?")))
          .child(div().flex_shrink(0).max_w(150).truncate().text_color(t.foreground).child(w.name))
          .child(g ? this.gitTail(g, tree, w.name, t) : div().flex_1())
          .when(Boolean(prefix && w.machine), el => el.child(div().text_size(10).text_color(t.dim).child(w.machine)))
          .child(div().id(`${prefix}tags-${w.id}`).px(4).text_size(10).text_color(t.dim).cursor_pointer()
            .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
            .on_mouse_up("left", (_e, cx) => cx.stop_propagation())
            .on_click((_e, cx) => {
              cx.stop_propagation();
              this.editingTags = w.id;
              this.panel = "tags";
              this.tagsInput.set_value((this.tags[w.id] ?? []).join(", "));
              this.tagsInput.focus();
              cx.notify();
            }).child(`#${(this.tags[w.id] ?? []).length || ""}`))
          .child(this.summary(w, t, prefix)),
      );
  }

  compact({ w, i }, t, prefix = "") {
    return h_flex()
      .id(`${prefix}space-${w.id}`)
      .h(26)
      .flex_none()
      .justify_center()
      .gap(4)
      .when(w.active, (el) => el.bg(t.raised))
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("space.select", { id: w.id }))
      .child(div().text_color(w.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().text_color(tone(t, w.status)).child(glyph(w.status)));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    this.bySpace = new Map();
    const list = agents();
    this.listed = new Set(list.map(a => a.address));
    for (const a of list) {
      if (!this.bySpace.has(a.space)) this.bySpace.set(a.space, []);
      this.bySpace.get(a.space).push(a);
    }
    this.childrenByParent = new Map();
    for (const k of terminals()) {
      if (!k.parent || k.state !== "live") continue;
      if (!this.childrenByParent.has(k.parent)) this.childrenByParent.set(k.parent, []);
      this.childrenByParent.get(k.parent).push(k);
    }
    const order = [];
    const orderedAddresses = new Set();
    const append = a => {
      if (orderedAddresses.has(a.address)) return;
      orderedAddresses.add(a.address);
      order.push(a.address);
      for (const k of this.childrenByParent.get(a.address) ?? []) if (!this.listed.has(k.address)) append(k);
    };
    const visible = this.visibleGroups();
    for (const group of visible) for (const {w} of group.rows) {
      if (!this.spaceFolded.has(w.id)) for (const a of this.bySpace.get(w.id) ?? []) append(a);
    }
    setAgentOrder(order);
    const palette = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
    const sp = spaces();
    const ids = new Set(sp.map(p => p.id));
    const kept = Object.fromEntries(Object.entries(shared("space.colors") ?? {}).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(shared("space.colors") ?? {}).length;
    for (const p of sp) {
      if (kept[p.id] || p.name === "~") continue;
      const uses = c => Object.values(kept).filter(v => v === c).length;
      kept[p.id] = palette.reduce((best, c) => uses(c) < uses(best) ? c : best);
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
    const filtering = Boolean(this.view.query.trim() || this.view.tag || this.view.status);
    const grouping = this.view.group !== "none";
    const headerControl = (id, name, icon, active) => div().id(id).relative().p(4).rounded(5).cursor_pointer()
      .text_color(active ? t.accent : t.dim)
      .when(active || this.panel === name, s => s.bg(t.raised))
      .tooltip(({ views: "Saved views", groups: "Group spaces", filters: "Filter spaces" })[name] + (active ? " · active" : ""))
      .accessibility_label(({ views: "Saved views", groups: "Group spaces", filters: "Filter spaces" })[name] + (active ? ": active" : ""))
      .hover(s => s.bg(t.hover))
      .on_click((_e, cx) => { this.panel = this.panel === name ? null : name; this.editingTags = null; cx.notify(); })
      .child(svg(icon).size(14).text_color(active ? t.accent : t.dim))
      .when(active, s => s.child(div().absolute().right(1).top(1).size(4).rounded(2).bg(t.accent)));
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).pl(16).pr(10).items_center().text_size(11.5).text_color(t.dim)
        .when(!collapsed, el => el.child(div().flex_1().child("Spaces")))
        .child(h_flex().gap(2).items_center()
          .when(!collapsed, el => el
            .child(headerControl("space-views", "views", "mods/workspace-chrome/archive.svg", false))
            .child(headerControl("space-groups", "groups", "mods/workspace-chrome/layers.svg", grouping))
            .child(headerControl("space-controls", "filters", "mods/space-agents/filter.svg", filtering)))
          .child(div().id("space-new").p(4).rounded(5).hover(s => s.bg(t.hover).text_color(t.foreground)).on_click(() => run("space.new")).child("+"))))
      .when(!collapsed && Boolean(this.panel), el => el.child(this.controls(t)))
      .child(v_flex().flex_1().min_h(0).px(8).pb(14).overflow_y_scrollbar().mode("always")
        .on_mouse_up("left", (_e, cx) => { this.pressed = null; cx.notify(); })
        .children(this.grouped(t, collapsed)));
  }
}
