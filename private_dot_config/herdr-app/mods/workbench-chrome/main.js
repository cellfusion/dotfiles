// Generated from workbench-chrome/main.ts; edit the TypeScript source.
import { View, div, image, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { focused, layout, panes, props, run, setShared, shared, spaces, theme, window } from "herdr";
import { resolveTarget } from "./target.js";
function target() {
    const allSpaces = spaces();
    const allPanes = panes();
    const focus = focused();
    const space = allSpaces.find((item) => item.active) ?? null;
    const { cwd, machine } = resolveTarget({}, focus, allSpaces, allPanes);
    const tab = space?.tabs.find((item) => item.active);
    const current = tab && focus?.space === space?.id && focus?.tab === tab.id && focus?.terminal
        ? allPanes.find((pane) => pane.tab === tab.id && pane.terminal === focus.terminal && pane.cwd === cwd)
        : null;
    const matchingPane = current ?? allPanes.find((pane) => pane.tab === tab?.id && pane.terminal && pane.cwd === cwd);
    return { space, cwd, machine, branch: cwd ? matchingPane?.branch ?? null : null };
}
function findSidebar(node) {
    if (!node || typeof node !== "object")
        return null;
    if (node.id === "sidebar")
        return node;
    for (const child of node.children ?? []) {
        const found = findSidebar(child);
        if (found)
            return found;
    }
    return null;
}
const narrow = () => (findSidebar(layout())?.size?.px ?? Infinity) < 160;
function toggleSidebar() {
    const collapsed = narrow();
    const width = findSidebar(layout())?.size?.px;
    if (!collapsed && typeof width === "number")
        setShared("sidebar.width", width);
    setShared("sidebar.collapsed", !collapsed);
    const saved = shared("sidebar.width");
    run("layout.resize", { id: "sidebar", px: collapsed ? (typeof saved === "number" && saved >= 160 ? saved : 268) : window()?.platform === "macos" ? 76 : 44 });
}
function renderBrand() {
    const t = theme();
    const collapsed = narrow();
    const button = (id, glyph, action) => div().id(id).size(26).flex_none().flex()
        .items_center().justify_center().rounded(6).text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_event, cx) => cx.stop_propagation()).on_click(action)
        .child(svg(`mods/workspace-chrome/${glyph}.svg`).size(15));
    return h_flex().size_full().bg(t.chrome).pl(collapsed ? 6 : 14).pr(10).gap(4).items_center().text_size(13.5)
        .when(window()?.platform === "macos" && !window()?.fullscreen && !collapsed, el => el.pl(76))
        .when(!collapsed, el => el.child(h_flex().flex_1().gap(8).items_center()
        .child(image("frame/welcome/herdr.png").size(20).rounded(5))
        .child(div().font_semibold().text_color(t.foreground).child("Herdr"))))
        .when(!collapsed, el => el.child(button("search", "search", () => run("mod.open", { name: "workbench-navigator" }))))
        .when(!(collapsed && window()?.platform === "macos"), el => el.child(button("sidebar-toggle", "sidebar", toggleSidebar)));
}
export default class WorkbenchChrome extends View {
    render() {
        if (props()?.mode === "brand")
            return renderBrand();
        // Herdr supplies concrete colors as strings; GPUI's API requires hex colors.
        const t = theme();
        const current = target();
        const space = current.space;
        return h_flex().size_full().min_w(0).px(12).gap(12).items_center()
            .bg(t.chrome).border_t(1).border_color(t.border).text_size(12).text_color(t.muted)
            .child(div().flex_none().text_color(t.accent).child(space ? (current.machine ?? "local") : "no space"))
            .when(Boolean(space), el => el.child(div().flex_none().child(space.name)))
            .when(Boolean(current.branch), el => el.child(div().flex_none().text_color(t.foreground).child(`git:${current.branch}`)))
            .child(div().min_w(0).truncate().text_color(t.dim).child(current.cwd ?? "no target directory"));
    }
}
