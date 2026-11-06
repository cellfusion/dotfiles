// Generated from workbench-navigator/picker.ts; edit the TypeScript source.
import { div, svg } from "gpui-kit";
import { h_flex, v_flex, Input, InputState } from "gpui-base";
import { agents, closeOverlay, machines, panes, props, run, settings, spaces, terminals, theme } from "herdr";
import { agentSummary, groupPriority, workspaceEntries, workspaceLocations } from "./model.js";
const isChoice = (row) => row.kind !== "heading";
const key = (row) => {
    switch (row.kind) {
        case "space": return JSON.stringify([row.kind, row.space.id]);
        case "tab": return JSON.stringify([row.kind, row.space.id, row.tab.id]);
        case "new-tab": return JSON.stringify([row.kind, row.space]);
        case "new-space": return JSON.stringify([row.kind, row.machine]);
    }
};
const heightOf = (row) => row.kind === "heading" ? 22 : row.kind === "space" ? (row.activity ? 58 : 44) : row.kind === "tab" ? 26 : 28;
const matches = (query, fields) => {
    const text = fields.filter(Boolean).join(" ").toLowerCase();
    return !query || query.split(/\s+/).every(term => text.includes(term));
};
const reportText = (entry) => {
    const report = entry.agent && entry.status && entry.terminal?.report?.state === entry.status ? entry.terminal.report : null;
    const message = typeof report?.msg === "string" ? report.msg.slice(0, 512).replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim() : "";
    const progress = (entry.status === "working" || entry.status === "blocked") && Number.isInteger(report?.progress) && report.progress >= 0 && report.progress <= 100 ? `${report.progress}%` : "";
    return [message, progress].filter(Boolean).join(" · ");
};
const agentText = (entry) => entry.agent
    ? [entry.program, entry.title !== entry.address ? entry.title : null, reportText(entry)].filter((value) => typeof value === "string" && !!value)
    : [];
export class WorkbenchPicker {
    input;
    handle;
    filter = "";
    selectedKey = null;
    scroll = 0;
    actionScroll = 0;
    listHeight = 480;
    error = "";
    active = false;
    init(cx) {
        this.active = true;
        this.handle = cx.focus_handle();
        this.input = InputState.new({ placeholder: "Search workspaces, tabs and agents…" });
        this.input.on("change", (_event, eventCx) => {
            this.filter = this.input.value().trim().toLowerCase();
            this.selectedKey = null;
            this.scroll = 0;
            this.actionScroll = 0;
            this.error = "";
            eventCx.notify();
        });
        this.input.on("submit", (_event, eventCx) => {
            const choices = this.rows().filter(isChoice);
            const selected = this.selectedKey === null ? this.initialChoice(choices) : choices.find(row => key(row) === this.selectedKey);
            if (!selected && this.selectedKey !== null) {
                this.error = "Selected item is no longer available.";
                eventCx.notify();
            }
            else
                this.go(selected, eventCx);
        });
        this.input.focus();
        cx.timer.after(600, () => { if (this.active)
            this.input.focus(); });
    }
    close() { this.active = false; }
    initialChoice(choices) {
        if (!this.filter)
            return choices.find(row => row.kind === "tab" && row.space.active && row.tab.active) ?? choices[0];
        const first = choices[0];
        return first?.kind === "space" ? choices.find(row => row.kind === "tab" && row.space.id === first.space.id) ?? first : first;
    }
    rows() {
        const allSpaces = spaces(), allPanes = panes(), allTerminals = terminals(), allAgents = agents();
        const entries = workspaceEntries(allSpaces, allPanes, allAgents, allTerminals);
        const agentTabs = new Map(allAgents.map(agent => [agent.address, agent.tab]));
        const locations = workspaceLocations(allSpaces, allPanes, allTerminals, allAgents);
        const groups = [[], [], [], []];
        const machineStates = new Map(machines().map(machine => [machine.name, machine.layout]));
        // The sidebar preserves the first-seen workspace order within each priority.
        const orderedSpaces = [...new Map(entries.map(entry => [entry.space.id, entry.space])).values()];
        for (const space of orderedSpaces) {
            const mine = entries.filter(entry => entry.space.id === space.id);
            const priority = groupPriority(mine);
            // A space's configured starting folder is not its current terminal directory.
            const hasTerminal = allAgents.some(agent => agent.space === space.id) || allPanes.some(pane => pane.terminal && space.tabs.some(tab => tab.id === pane.tab));
            const cwd = hasTerminal ? locations.get(space.id) : null;
            const start = !hasTerminal && typeof space.folder === "string" ? space.folder : null;
            const workspaceFields = [space.name, space.branch, cwd, start, space.machine];
            const orphans = [];
            const byAddress = new Map();
            for (const entry of mine)
                if (entry.address)
                    byAddress.set(entry.address, entry);
            const byTab = new Map();
            const tabOf = (value) => value.pane?.tab ?? (value.address ? agentTabs.get(value.address) : undefined);
            for (const entry of mine) {
                let current = entry;
                const seen = new Set();
                while (current && !tabOf(current) && current.parent && !seen.has(current.parent)) {
                    seen.add(current.parent);
                    current = byAddress.get(current.parent);
                }
                const tab = current && tabOf(current);
                if (tab)
                    byTab.set(tab, [...(byTab.get(tab) ?? []), entry]);
                else
                    orphans.push(entry);
            }
            const matchingTabs = space.tabs.filter(tab => matches(this.filter, [...workspaceFields, tab.name, ...(byTab.get(tab.id) ?? []).flatMap(agentText)]));
            if (!matches(this.filter, workspaceFields) && !matchingTabs.length && !orphans.some(entry => matches(this.filter, [...workspaceFields, ...agentText(entry)])))
                continue;
            const machine = space.machine ?? "This computer";
            const state = machineStates.get(space.machine ?? null);
            const machineLabel = state === "unavailable" ? `${machine} (unavailable)` : state === "loading" ? `${machine} (loading)` : machine;
            const location = [machineLabel, space.branch ? `Branch: ${space.branch}` : null, cwd || (start ? `Start: ${start}` : "Directory unavailable")].filter(Boolean).join(" · ");
            const activity = orphans.map(entry => agentText(entry).join(" · ")).filter(Boolean).join("  |  ");
            groups[priority].push({ kind: "space", space, location, activity, counts: agentSummary(mine), priority });
            for (const tab of matchingTabs) {
                const members = byTab.get(tab.id) ?? [];
                groups[priority].push({ kind: "tab", space, tab, detail: members.map(entry => agentText(entry).join(" · ")).filter(Boolean).join("  |  "), priority: groupPriority(members) });
            }
        }
        const labels = ["Needs attention", "Done", "Working", "Other"];
        const rows = [];
        groups.forEach((group, priority) => { if (group.length)
            rows.push({ kind: "heading", priority, label: labels[priority] }, ...group); });
        const active = allSpaces.find(space => space.active)?.id ?? null;
        if (matches(this.filter, ["new tab"]))
            rows.push({ kind: "new-tab", space: active });
        if (matches(this.filter, ["new space", "local", "this computer"]))
            rows.push({ kind: "new-space", machine: null });
        for (const machine of machines()) {
            if (machine.name && machine.layout === "ready" && matches(this.filter, ["new space", machine.name]))
                rows.push({ kind: "new-space", machine: machine.name });
        }
        return rows;
    }
    go(row, cx) {
        if (!row)
            return;
        if (row.kind === "tab") {
            if (!spaces().some(space => space.id === row.space.id && space.tabs.some(tab => tab.id === row.tab.id))) {
                this.error = "This tab is no longer available.";
                cx.notify();
                return;
            }
            closeOverlay(props().overlay);
            run("tab.select", { id: row.tab.id });
        }
        else if (row.kind === "space") {
            if (!spaces().some(space => space.id === row.space.id)) {
                this.error = "This space is no longer available.";
                cx.notify();
                return;
            }
            closeOverlay(props().overlay);
            run("space.select", { id: row.space.id });
        }
        else if (row.kind === "new-tab") {
            if ((spaces().find(space => space.active)?.id ?? null) !== row.space) {
                this.error = "The selected space is no longer available.";
                cx.notify();
                return;
            }
            closeOverlay(props().overlay);
            run("tab.new", row.space ? { space: row.space } : undefined);
        }
        else {
            if (!machines().some(machine => machine.name === row.machine && machine.layout === "ready")) {
                this.error = "The selected machine is no longer available.";
                cx.notify();
                return;
            }
            closeOverlay(props().overlay);
            run("space.new", { machine: row.machine ?? "" });
        }
    }
    render(_cx) {
        const t = theme();
        const rows = this.rows(), choices = rows.filter(isChoice);
        if (this.selectedKey === null && choices.length)
            this.selectedKey = key(this.initialChoice(choices));
        const selected = choices.find(row => key(row) === this.selectedKey);
        const workspaceRows = rows.filter(row => row.kind !== "new-tab" && row.kind !== "new-space");
        const actionRows = rows.filter(row => row.kind === "new-tab" || row.kind === "new-space");
        const draw = (row) => {
            const marks = ["!", "✓", "▶", "·"];
            const tones = [t.blocked, t.done, t.working, t.dim];
            if (row.kind === "heading")
                return div().id(`picker-status-${["attention", "done", "working", "other"][row.priority]}`)
                    .h(22).px(10).text_size(11).font_semibold().text_color(tones[row.priority]).child(row.label);
            const on = selected === row;
            if (row.kind === "space")
                return h_flex().id(`picker-space-${row.space.id}`).mx(4).px(10).h(heightOf(row)).items_center().rounded(7)
                    .cursor_pointer().tooltip([row.space.name, row.location, row.activity].filter(Boolean).join(" · "))
                    .when(on, el => el.bg(t.hover)).hover(el => el.bg(t.hover)).on_click((_event, cx) => this.go(row, cx))
                    .child(div().w(16).flex_none().text_color(tones[row.priority]).child(marks[row.priority]))
                    .child(v_flex().flex_1().min_w(0)
                    .child(h_flex().items_center().gap(6)
                    .child(div().flex_1().min_w(0).truncate().font_medium().text_color(t.foreground).child(row.space.name))
                    .when(row.counts.error > 0, el => el.child(div().text_size(10).text_color(t.blocked).tooltip(`${row.counts.error} errors`).child(`×${row.counts.error}`)))
                    .when(row.counts.blocked > 0, el => el.child(div().text_size(10).text_color(t.blocked).tooltip(`${row.counts.blocked} waiting`).child(`!${row.counts.blocked}`)))
                    .when(row.counts.done > 0, el => el.child(div().text_size(10).text_color(t.done).tooltip(`${row.counts.done} unseen`).child(`✓${row.counts.done}`)))
                    .when(row.counts.working > 0, el => el.child(div().text_size(10).text_color(t.working).tooltip(`${row.counts.working} working`).child(`▶${row.counts.working}`)))
                    .when(row.counts.total > 0 && !(row.counts.error || row.counts.blocked || row.counts.done || row.counts.working), el => el.child(div().text_size(10).text_color(t.dim).tooltip(`${row.counts.total} agents`).child(String(row.counts.total)))))
                    .child(div().truncate().text_size(11).text_color(t.muted).child(row.location))
                    .when(!!row.activity, el => el.child(div().truncate().text_size(11).text_color(t.dim).child(row.activity))));
            if (row.kind === "tab")
                return h_flex().id(`picker-tab-${row.tab.id}`).mx(4).pl(38).pr(10).h(26).gap(5).items_center().rounded(5)
                    .cursor_pointer().tooltip([row.tab.name, row.detail].filter(Boolean).join(" · "))
                    .when(on, el => el.bg(t.hover)).hover(el => el.bg(t.hover)).on_click((_event, cx) => this.go(row, cx))
                    .child(div().w(12).flex_none().text_color(tones[row.priority]).child(marks[row.priority]))
                    .child(div().max_w(130).flex_none().truncate().text_size(11).text_color(t.muted).child(row.tab.name))
                    .when(!!row.detail, el => el.child(div().text_size(11).text_color(t.dim).child("·"))
                    .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.muted).child(row.detail)));
            const label = row.kind === "new-tab" ? "New tab" : row.machine ? `New space on ${row.machine}` : "New space on this computer";
            const id = row.kind === "new-tab" ? "picker-new-tab" : `picker-new-space-${row.machine ?? "local"}`;
            return h_flex().id(id).mx(4).px(10).h(28).gap(8).items_center().rounded(7).cursor_pointer()
                .when(on, el => el.bg(t.hover)).hover(el => el.bg(t.hover)).on_click((_event, cx) => this.go(row, cx))
                .child(div().w(12).text_color(t.dim).child("+")).child(div().truncate().text_color(t.muted).child(label));
        };
        const list = (items, limit, actions) => {
            const tops = [];
            let total = 0;
            for (const row of items) {
                tops.push(total);
                total += heightOf(row);
            }
            const height = Math.min(limit, total), maxScroll = Math.max(0, total - height);
            let scroll = Math.max(0, Math.min(actions ? this.actionScroll : this.scroll, maxScroll));
            const selectedIndex = selected ? items.indexOf(selected) : -1;
            if (selectedIndex >= 0) {
                if (tops[selectedIndex] < scroll)
                    scroll = tops[selectedIndex];
                if (tops[selectedIndex] + heightOf(items[selectedIndex]) > scroll + height)
                    scroll = tops[selectedIndex] + heightOf(items[selectedIndex]) - height;
            }
            if (actions)
                this.actionScroll = scroll;
            else
                this.scroll = scroll;
            return v_flex().id(actions ? "picker-actions" : "picker-list").min_h(0)
                .when(actions, el => el.h(height).flex_none())
                .when(!actions, el => el.h(480).flex_1().on_size_change((size, cx) => {
                const zoom = settings().zoom;
                const next = size.height / (typeof zoom === "number" && zoom > 0 ? zoom : 1);
                if (next > 0 && next !== this.listHeight) {
                    this.listHeight = next;
                    cx.notify();
                }
            }))
                .when(total > height, el => el.overflow_hidden().on_scroll_wheel((event, cx) => {
                const next = Math.max(0, Math.min(scroll - event.delta.y, maxScroll));
                if (actions)
                    this.actionScroll = next;
                else
                    this.scroll = next;
                const visible = items.filter((row, i) => isChoice(row) && tops[i] + heightOf(row) > next && tops[i] < next + height).filter(isChoice);
                if (visible.length && (!selected || !visible.includes(selected)))
                    this.selectedKey = key(visible[event.delta.y < 0 ? visible.length - 1 : 0]);
                cx.notify();
            }))
                .children(items.map((row, i) => {
                if (total > height && (tops[i] + heightOf(row) <= scroll || tops[i] >= scroll + height))
                    return null;
                const el = draw(row);
                return total > height ? el.absolute().left(0).right(0).top(tops[i] - scroll).bottom(height - (tops[i] + heightOf(row) - scroll)) : el;
            }).filter((el) => el !== null));
        };
        return v_flex().id("picker").track_focus(this.handle).size_full().min_h(0).p(18).gap(8).bg(t.popover).text_size(13)
            .on_key_down((event, cx) => {
            if (event.key === "escape") {
                closeOverlay(props().overlay);
                cx.stop_propagation();
                return;
            }
            if (event.key === "d" && event.modifiers.control) {
                const current = this.selectedKey === null ? undefined : this.rows().filter(isChoice).find(row => key(row) === this.selectedKey);
                if (current?.kind === "tab" && spaces().some(space => space.id === current.space.id && space.tabs.some(tab => tab.id === current.tab.id))) {
                    closeOverlay(props().overlay);
                    run("tab.close", { id: current.tab.id });
                }
                else if (!current && this.selectedKey !== null) {
                    this.error = "Selected item is no longer available.";
                    cx.notify();
                }
                cx.stop_propagation();
                return;
            }
            if (event.key !== "up" && event.key !== "down")
                return;
            if (choices.length) {
                const index = this.selectedKey === null ? -1 : choices.findIndex(row => key(row) === this.selectedKey);
                const next = index < 0 ? (event.key === "down" ? 0 : choices.length - 1) : (index + (event.key === "down" ? 1 : choices.length - 1)) % choices.length;
                this.selectedKey = key(choices[next]);
                this.error = "";
            }
            cx.stop_propagation();
            cx.notify();
        })
            .child(h_flex().items_center().child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Go to…"))
            .child(div().text_size(11).text_color(t.dim).child("Esc")))
            .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
            .child(svg("mods/workspace-chrome/search.svg").size(15).text_color(t.dim))
            .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground)))
            .when(!!this.error, el => el.child(div().px(4).text_size(12).text_color(t.blocked).child(this.error)))
            .when(!rows.length, el => el.child(div().px(10).py(8).text_color(t.dim).child("No matches")))
            .child(list(workspaceRows, this.listHeight, false))
            .child(list(actionRows, 84, true))
            .child(div().text_size(10.5).text_color(t.muted).child("↑↓ Select · Enter Open · Ctrl+D Close tab"));
    }
}
