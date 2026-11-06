import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, v_virtual_list, VirtualListScrollHandle, Scrollbar } from "gpui-base";
import { props, exec, closeOverlay, notify, theme, settings, focused, spaces, panes } from "herdr";
import { resolveTarget } from "./target.js";
import { itemKey } from "./identity.js";
import { readDiff } from "./diff.js";

const SECTIONS = [
  { id: "mine", label: "My PRs", query: "is:pr is:open author:@me" },
  { id: "review", label: "Review requested", query: "is:pr is:open review-requested:@me" },
  { id: "assigned", label: "Assigned issues", query: "is:issue is:open assignee:@me" },
  { id: "prs", label: "Repository open PRs", kind: "pr" },
  { id: "issues", label: "Repository open issues", kind: "issue" },
];

function errorText(error) { return error instanceof Error ? error.message : String(error); }
function button(id, label, active, t, click) {
  return div().id(id).px(9).py(5).cursor_pointer().bg(active ? t.selected : t.raised)
    .text_color(active ? t.foreground : t.muted).hover((s) => s.bg(t.hover)).on_click(click).child(label);
}
function repoFromUrl(url) {
  const match = /^https?:\/\/([^/:?#]+)\/([^/?#]+)\/([^/?#]+)\/?(?:[?#].*)?$/.exec(url || "");
  if (!match) throw new Error("The current repository has an unsupported URL; cannot determine its GitHub host safely.");
  return { host: match[1], owner: match[2], repo: match[3].replace(/\.git$/, "") };
}
function searchItem(raw, host, kind) {
  const match = /^https?:\/\/([^/:?#]+)\/([^/?#]+)\/([^/?#]+)\/(pull|issues)\/(\d+)(?:[?#].*)?$/.exec(raw.html_url || "");
  if (!match || match[1].toLowerCase() !== host.toLowerCase() || !Number.isSafeInteger(raw.number) || raw.number < 1 || Number(match[5]) !== raw.number || match[4] !== (kind === "pr" ? "pull" : "issues"))
    throw new Error("Search returned an item with an invalid or different-host repository URL.");
  return { host, owner: match[2], repo: match[3], kind, number: raw.number, title: raw.title, author: raw.user?.login, updatedAt: raw.updated_at };
}
function repoItem(raw, repository, kind) {
  if (!Number.isSafeInteger(raw.number) || raw.number < 1) throw new Error("The repository returned an item without a valid number.");
  return { ...repository, kind, number: raw.number, title: raw.title, author: raw.user?.login, updatedAt: raw.updated_at };
}

export default class WorkbenchGitHub extends View {
  init(_props, cx) {
    const p = props() ?? {};
    const target = resolveTarget(p, focused(), spaces(), panes());
    this.cwd = target.cwd; this.machine = target.machine; this.overlay = p.overlay;
    this.handle = cx.focus_handle(); this.handle.focus();
    this.listScroll = VirtualListScrollHandle.new();
    this.filterInput = InputState.new({ placeholder: "Filter title, repository, author or number" });
    this.filter = ""; this.editingFilter = false;
    this.filterInput.on("focus", (_e, cx) => { this.editingFilter = true; cx.notify(); });
    this.filterInput.on("blur", (_e, cx) => { this.editingFilter = false; cx.notify(); });
    this.filterInput.on("submit", (_e, cx) => { this.handle.focus(); cx.notify(); });
    this.filterInput.on("change", (_e, cx) => { this.filter = this.filterInput.value(); this.ensureSelection(cx); this.scrollSelection(); cx.notify(); });
    this.sections = SECTIONS.map((section) => ({ ...section, items: [], loading: false, error: null, incomplete: false }));
    this.activeSection = 0; this.selected = null; this.detail = null; this.detailError = null;
    this.detailLoading = false; this.diff = null; this.diffLines = []; this.diffError = null; this.diffLoading = false;
    this.contentScroll = VirtualListScrollHandle.new(); this.contentWidth = 320; this.contentHeight = 0; this.contentIndex = 0;
    this.bodyRows = []; this.diffRows = [];
    this.cleanupError = null;
    this.diffJobs = 0; this.diffDirectories = new Set(); this.closing = false;
    this.detailMode = "detail"; this.listGeneration = 0; this.detailGeneration = 0; this.diffGeneration = 0;
    this.refresh(cx);
  }

  async close() {
    this.closing = true; ++this.diffGeneration;
    if (this.diffJobs) {
      const paths = [...this.diffDirectories];
      notify({ title: "GitHub diff interrupted", body: `A PR diff download or cleanup may still be running on ${this.machine ?? "local"}. Private temporary directories: ${paths.length ? paths.join(", ") : "not yet known (/tmp/herdr-gh.*)"}. Check the process before removing them.`, level: "error" });
    }
  }

  async gh(args, json = true) {
    let result;
    try { result = await exec("gh", args, { cwd: this.cwd, on: this.machine }); }
    catch (error) { throw new Error(`Could not start gh on the selected machine: ${errorText(error)}`); }
    if (result.code !== 0) throw new Error((result.stderr || result.stdout || `gh exited ${result.code}`).trim());
    if (!json) return result.stdout;
    try { return JSON.parse(result.stdout); }
    catch (error) { throw new Error(`gh returned invalid JSON: ${errorText(error)}`); }
  }

  visible(section) {
    const query = this.filter.trim().toLowerCase();
    if (!query) return section.items;
    return section.items.filter((item) => `${item.owner}/${item.repo} #${item.number} ${item.title || ""} ${item.author || ""}`.toLowerCase().includes(query));
  }

  refresh(cx) {
    const generation = ++this.listGeneration;
    ++this.detailGeneration; ++this.diffGeneration;
    this.selected = null; this.detail = null; this.detailError = null; this.detailLoading = false;
    this.diff = null; this.diffLines = []; this.diffError = null; this.diffLoading = false;
    this.bodyRows = []; this.diffRows = []; this.contentIndex = 0;
    for (const section of this.sections) { section.items = []; section.error = null; section.incomplete = false; section.loading = Boolean(this.cwd); }
    if (!this.cwd) {
      for (const section of this.sections) section.error = "No unambiguous working directory. Focus a repository terminal and reopen GitHub.";
      cx.notify(); return;
    }
    cx.notify();
    cx.spawn(async (cx) => {
      let repository;
      try {
        const info = await this.gh(["repo", "view", "--json", "nameWithOwner,url"]);
        repository = repoFromUrl(info.url);
        if (`${repository.owner}/${repository.repo}`.toLowerCase() !== String(info.nameWithOwner || "").toLowerCase())
          throw new Error("Repository URL and name do not match; refusing to choose a host.");
      } catch (error) {
        if (generation !== this.listGeneration) return;
        for (const section of this.sections) { section.loading = false; section.error = errorText(error); }
        cx.notify(); return;
      }
      if (generation !== this.listGeneration) return;
      for (const section of this.sections) {
        cx.spawn(async (cx) => {
          try {
            let items, incomplete = false;
            if (section.query || section.kind === "issue") {
              const query = section.query || `is:issue is:open repo:${repository.owner}/${repository.repo}`;
              const endpoint = `search/issues?q=${encodeURIComponent(query)}&per_page=100&sort=updated&order=desc`;
              const response = await this.gh(["api", "--hostname", repository.host, endpoint]);
              if (!Array.isArray(response.items)) throw new Error("Unexpected search response.");
              incomplete = response.incomplete_results === true;
              items = response.items.slice(0, 100).map((item) => searchItem(item, repository.host, section.id === "assigned" || section.kind === "issue" ? "issue" : "pr"));
              if (!section.query && items.some((item) => item.owner.toLowerCase() !== repository.owner.toLowerCase() || item.repo.toLowerCase() !== repository.repo.toLowerCase()))
                throw new Error("Search returned an item from a different repository.");
            } else {
              const base = `repos/${encodeURIComponent(repository.owner)}/${encodeURIComponent(repository.repo)}`;
              const endpoint = `${base}/pulls?state=open&per_page=100&sort=updated&direction=desc`;
              const response = await this.gh(["api", "--hostname", repository.host, endpoint]);
              if (!Array.isArray(response)) throw new Error("Unexpected repository list response.");
              items = response.slice(0, 100).map((item) => repoItem(item, repository, section.kind));
            }
            if (generation !== this.listGeneration) return;
            section.items = items;
            section.incomplete = incomplete;
          } catch (error) {
            if (generation !== this.listGeneration) return;
            section.error = errorText(error);
          }
          section.loading = false;
          if (this.sections[this.activeSection] === section) { this.ensureSelection(cx); this.scrollSelection(); }
          cx.notify();
        });
      }
    });
  }

  ensureSelection(cx) {
    const items = this.visible(this.sections[this.activeSection]);
    if (this.selected && items.some((item) => itemKey(item) === itemKey(this.selected))) return;
    if (items.length) this.select(items[0], cx);
    else {
      ++this.detailGeneration; ++this.diffGeneration; this.selected = null;
      this.detail = null; this.detailError = null; this.detailLoading = false;
      this.diff = null; this.diffLines = []; this.diffError = null; this.diffLoading = false;
      this.bodyRows = []; this.diffRows = []; this.contentIndex = 0;
    }
  }

  scrollSelection() {
    const items = this.visible(this.sections[this.activeSection]);
    const index = items.findIndex((item) => this.selected && itemKey(item) === itemKey(this.selected));
    if (index >= 0) this.listScroll.scroll_to_item(index, "center");
  }

  rebuildContent() {
    const splitRows = (lines, wrapWords, width) => {
      const rows = [];
      for (const line of lines) {
        if (!line.length) { rows.push({ text: "", line }); continue; }
        let start = 0, index = 0, count = 0;
        while (index < line.length) {
          const code = line.codePointAt(index), size = code === 9 ? 4 : code >= 0x1100 ? 2 : 1;
          if (index > start && count + size > width) {
            let end = index;
            if (wrapWords) {
              const space = line.lastIndexOf(" ", index - 1);
              if (space >= start + Math.floor(width / 2)) end = space + 1;
            }
            rows.push({ text: line.slice(start, end), line }); start = end; index = end; count = 0;
            continue;
          }
          index += code > 0xffff ? 2 : 1; count += size;
        }
        rows.push({ text: line.slice(start), line });
      }
      return rows;
    };
    this.bodyRows = this.detail ? splitRows((this.detail.body || "No description.").split("\n"), true, Math.max(1, Math.floor((this.contentWidth - 40) / 12))) : [];
    this.diffRows = splitRows(this.diffLines, false, Math.max(1, Math.floor((this.contentWidth - 40) / 16)));
  }

  activate(index, cx) {
    this.activeSection = index; this.ensureSelection(cx); this.scrollSelection(); this.handle.focus(); cx.notify();
  }

  select(item, cx) {
    const key = itemKey(item), generation = ++this.detailGeneration;
    ++this.diffGeneration; this.selected = item; this.detail = null; this.detailError = null; this.detailLoading = true;
    this.diff = null; this.diffLines = []; this.diffError = null; this.diffLoading = false;
    this.bodyRows = []; this.diffRows = []; this.contentIndex = 0; this.contentScroll.scroll_to_item(0, "top");
    if (item.kind !== "pr") this.detailMode = "detail";
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const endpoint = `repos/${encodeURIComponent(item.owner)}/${encodeURIComponent(item.repo)}/${item.kind === "pr" ? "pulls" : "issues"}/${item.number}`;
        const detail = await this.gh(["api", "--hostname", item.host, endpoint]);
        if (generation !== this.detailGeneration || !this.selected || itemKey(this.selected) !== key) return;
        if (!detail || typeof detail !== "object" || detail.number !== item.number) throw new Error("Unexpected detail response.");
        this.detail = detail; this.rebuildContent();
      } catch (error) {
        if (generation !== this.detailGeneration || !this.selected || itemKey(this.selected) !== key) return;
        this.detailError = errorText(error);
      }
      this.detailLoading = false; cx.notify();
    });
    if (this.detailMode === "diff" && item.kind === "pr") this.loadDiff(cx);
  }

  loadDiff(cx) {
    const item = this.selected;
    if (!item || item.kind !== "pr" || this.diffLoading || this.diff !== null) return;
    const key = itemKey(item), generation = ++this.diffGeneration;
    this.diffLoading = true; this.diffError = null; this.diffJobs++; cx.notify();
    cx.spawn(async (cx) => {
      try {
        const diff = await readDiff(exec, { cwd: this.cwd, machine: this.machine }, item,
          () => generation === this.diffGeneration && Boolean(this.selected) && itemKey(this.selected) === key,
          (directory) => {
            this.diffDirectories.add(directory);
            if (this.closing) notify({ title: "GitHub diff interrupted", body: `Private temporary directory on ${this.machine ?? "local"}: ${directory}. Check the process before removing it.`, level: "error" });
          },
          (directory) => { this.diffDirectories.delete(directory); });
        if (generation !== this.diffGeneration || !this.selected || itemKey(this.selected) !== key) return;
        this.diff = diff; this.diffLines = diff ? diff.split("\n") : []; this.rebuildContent();
      } catch (error) {
        if (error?.cleanupFailed) {
          this.cleanupError = errorText(error);
          if (this.closing) notify({ title: "GitHub cleanup failed", body: this.cleanupError, level: "error" });
          else cx.notify();
        }
        if (generation !== this.diffGeneration || !this.selected || itemKey(this.selected) !== key) return;
        this.diffError = errorText(error);
      } finally {
        this.diffJobs--;
      }
      this.diffLoading = false; cx.notify();
    });
  }

  mode(mode, cx) {
    this.detailMode = mode;
    this.contentIndex = 0; this.contentScroll.scroll_to_item(0, "top");
    if (mode === "diff") this.loadDiff(cx);
    this.handle.focus(); cx.notify();
  }

  key(event, cx) {
    if (this.editingFilter) {
      cx.stop_propagation();
      if (event.key === "escape") { this.handle.focus(); cx.notify(); }
      return;
    }
    const key = event.keystroke;
    if (key === "/") { cx.stop_propagation(); this.filterInput.focus(); return; }
    if (key === "r") { cx.stop_propagation(); this.refresh(cx); return; }
    if (key === "d" && this.selected?.kind === "pr") { cx.stop_propagation(); this.mode(this.detailMode === "diff" ? "detail" : "diff", cx); return; }
    if (key === "h" || key === "left") { cx.stop_propagation(); this.activate((this.activeSection + SECTIONS.length - 1) % SECTIONS.length, cx); return; }
    if (key === "l" || key === "right" || key === "tab") { cx.stop_propagation(); this.activate((this.activeSection + 1) % SECTIONS.length, cx); return; }
    if (/^[1-5]$/.test(key)) { cx.stop_propagation(); this.activate(Number(key) - 1, cx); return; }
    if (key === "pagedown" || key === "pageup") {
      cx.stop_propagation();
      const rows = this.detailMode === "diff" ? this.diffRows : this.bodyRows;
      if (rows.length) {
        const step = Math.max(1, Math.floor(this.contentHeight / 22) - 1);
        this.contentIndex = Math.max(0, Math.min(rows.length - 1, this.contentIndex + (key === "pagedown" ? step : -step)));
        this.contentScroll.scroll_to_item(this.contentIndex, "top"); cx.notify();
      }
      return;
    }
    if (key === "j" || key === "down" || key === "k" || key === "up") {
      cx.stop_propagation();
      const items = this.visible(this.sections[this.activeSection]);
      const current = items.findIndex((item) => this.selected && itemKey(item) === itemKey(this.selected));
      const delta = key === "j" || key === "down" ? 1 : -1;
      const next = Math.max(0, Math.min(items.length - 1, current + delta));
      if (items[next]) {
        if (next !== current) this.select(items[next], cx);
        this.listScroll.scroll_to_item(next, "center");
      }
    }
  }

  render(cx) {
    const t = theme(), mono = settings().font_family ?? "JetBrains Mono", selected = this.selected, detail = this.detail;
    const section = this.sections[this.activeSection], items = this.visible(section);
    const sectionViews = this.sections.map((entry, index) => {
      const count = this.visible(entry).length;
      return h_flex().id(`github-section-header-${entry.id}`).flex_none().px(10).py(5).gap(6).cursor_pointer()
        .border_b(1).border_color(t.border).bg(index === this.activeSection ? t.selected : t.raised)
        .on_click((_e, cx) => this.activate(index, cx))
        .child(div().flex_1().min_w(0).truncate().font_semibold().child(`${index + 1}  ${entry.label}`))
        .child(div().text_color(entry.error || entry.incomplete ? t.ansi1 : t.dim).child(entry.loading ? "Loading…" : entry.error ? "Error" : `${count}${this.filter ? ` / ${entry.items.length}` : ""}${entry.incomplete ? " incomplete" : ""}`));
    });
    const list = v_virtual_list("github-rows", items.length, 44,
      (index) => itemKey(items[index]),
      (range) => items.slice(range.start, range.end).map((item) =>
        h_flex().h(44).px(10).py(5).gap(7).cursor_pointer()
          .when(selected && itemKey(selected) === itemKey(item), (el) => el.bg(t.selected))
          .child(div().text_color(t.accent).child(`#${item.number}`))
          .child(v_flex().flex_1().min_w(0)
            .child(div().truncate().child(item.title || "(untitled)"))
            .child(div().text_size(11).truncate().text_color(t.dim).child(`${item.owner}/${item.repo} · ${item.author || "Unknown author"}`)))))
      .size_full().track_scroll(this.listScroll)
      .on_item_click((key, cx) => {
        if (this.sections[this.activeSection] !== section) return;
        const item = this.visible(section).find((entry) => itemKey(entry) === key);
        if (item) { this.select(item, cx); this.handle.focus(); }
      });
    const contentRows = this.detailMode === "diff" ? this.diffRows : this.bodyRows;
    const contentList = v_virtual_list("github-content-lines", contentRows.length, 22,
      (index) => `${selected ? itemKey(selected) : ""}:${this.detailMode}:${index}`,
      (range) => {
        this.contentIndex = range.start;
        return contentRows.slice(range.start, range.end).map((row) => {
          const line = row.line;
          const color = this.detailMode !== "diff" ? t.foreground
            : line.startsWith("diff ") || line.startsWith("index ") || line.startsWith("---") || line.startsWith("+++") ? t.accent
            : line.startsWith("@@") ? t.ansi5 : line.startsWith("+") ? t.ansi2 : line.startsWith("-") ? t.ansi1 : t.foreground;
          return div().h(22).px(10).whitespace_nowrap().when(this.detailMode === "diff", (el) => el.font_family(mono)).text_color(color).child(row.text || " ");
        });
      }).size_full().track_scroll(this.contentScroll);
    return v_flex().id("workbench-github").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().min_h(0).bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(12)
      .child(h_flex().flex_none().h(42).px(12).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("GITHUB  /  DASHBOARD"))
        .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(`${this.machine || "local"} · ${this.cwd || "no directory"}`))
        .child(button("github-refresh", "Refresh  r", false, t, (_e, cx) => this.refresh(cx)))
        .child(button("github-close", "Close", false, t, () => closeOverlay(this.overlay))))
      .when(Boolean(this.cleanupError), (el) => el.child(div().flex_none().px(10).py(5).text_color(t.ansi1).child(this.cleanupError)))
      .child(h_flex().flex_none().items_center().gap(8).px(10).py(6).border_b(1).border_color(t.border)
        .child(div().text_color(t.accent).child("/"))
        .child(div().flex_1().min_w(0).bg(t.raised).px(8).py(4).child(Input.new(this.filterInput)))
        .child(div().text_color(t.dim).child("Filter loaded results · max 100 per section")))
      .child(h_flex().flex_1().min_h(0)
        .child(v_flex().id("github-list").w_1_3().h_full().min_w(0).flex_none().min_h(0).border_r(1).border_color(t.border)
          .children(sectionViews)
          .when(section.loading, (el) => el.child(div().px(10).py(7).text_color(t.dim).child("Loading entries…")))
          .when(Boolean(section.error), (el) => el.child(div().px(10).py(7).text_color(t.ansi1).child(section.error)))
          .when(section.incomplete, (el) => el.child(div().px(10).py(7).text_color(t.ansi1).child("Search results are incomplete; GitHub returned partial results.")))
          .when(!section.loading && !section.error && !section.incomplete && !items.length, (el) => el.child(div().px(10).py(7).text_color(t.dim).child(this.filter && section.items.length ? "No matching entries." : "No open entries.")))
          .child(v_flex().relative().flex_1().min_h(0).child(list).child(Scrollbar.vertical("github-rows").absolute().inset_0())))
        .child(v_flex().id("github-detail").flex_1().h_full().min_w(0).min_h(0)
          .child(h_flex().flex_none().gap(4).p(8).border_b(1).border_color(t.border)
            .child(button("github-detail-tab", "Details", this.detailMode === "detail", t, (_e, cx) => this.mode("detail", cx)))
            .when(selected?.kind === "pr", (el) => el.child(button("github-diff-tab", "PR diff  d", this.detailMode === "diff", t, (_e, cx) => this.mode("diff", cx)))))
          .when(Boolean(selected), (el) => el.child(v_flex().flex_none().px(14).py(8).gap(3).border_b(1).border_color(t.border)
            .child(div().text_color(t.accent).truncate().child(selected ? `${selected.host}/${selected.owner}/${selected.repo} · ${selected.kind === "pr" ? "PR" : "Issue"} #${selected.number}` : ""))
            .child(div().font_semibold().text_size(15).truncate().child(detail?.title || selected?.title || "(untitled)"))
            .child(div().text_color(t.muted).truncate().child(`${detail?.state || (this.detailLoading ? "Loading state…" : "")}${detail?.draft ? " · Draft" : ""} · ${detail?.user?.login || selected?.author || "Unknown author"}`))
            .when(Boolean(detail?.html_url), (header) => header.child(div().truncate().text_color(t.dim).child(detail.html_url)))))
          .child(v_flex().id("github-content").relative().flex_1().min_h(0)
            .on_size_change((size, cx) => {
              const width = Math.floor(size.width), height = Math.floor(size.height);
              if (width <= 0 || height <= 0) return;
              if (width !== this.contentWidth || height !== this.contentHeight) {
                this.contentWidth = width; this.contentHeight = height; this.rebuildContent();
                this.contentIndex = 0; this.contentScroll.scroll_to_item(0, "top"); cx.notify();
              }
            })
            .when(!selected, (body) => body.child(div().p(14).text_color(t.dim).child("Select an entry to read its details.")))
            .when(this.detailMode === "detail" && this.detailLoading, (body) => body.child(div().p(14).text_color(t.dim).child("Loading detail…")))
            .when(this.detailMode === "detail" && Boolean(this.detailError), (body) => body.child(div().p(14).text_color(t.ansi1).child(this.detailError)))
            .when(this.detailMode === "diff" && this.diffLoading, (body) => body.child(div().p(14).text_color(t.dim).child("Loading PR diff…")))
            .when(this.detailMode === "diff" && Boolean(this.diffError), (body) => body.child(div().p(14).text_color(t.ansi1).child(this.diffError)))
            .when(this.detailMode === "diff" && this.diff !== null && !contentRows.length, (body) => body.child(div().p(14).text_color(t.dim).child("Empty diff.")))
            .when(contentRows.length > 0, (body) => body.child(contentList).child(Scrollbar.vertical("github-content-lines").absolute().inset_0())))))
      .child(div().flex_none().px(10).py(6).border_t(1).border_color(t.border).text_color(t.dim)
        .child("1–5 / h l section  ·  j k move  ·  PgUp/PgDn read  ·  / filter  ·  d diff  ·  r refresh  ·  Esc close"));
  }
}
