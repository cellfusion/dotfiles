// Generated from workbench-chrome/target.ts; edit the TypeScript source.
export function resolveTarget(props, focus, spaces, panes) {
    if (Object.prototype.hasOwnProperty.call(props, "cwd")) {
        return { cwd: typeof props.cwd === "string" && props.cwd ? props.cwd : null, machine: typeof props.machine === "string" ? props.machine : null };
    }
    const space = spaces.find((item) => item.active);
    if (!space)
        return { cwd: null, machine: null };
    const machine = space.machine ?? null;
    const tab = space.tabs.find((item) => item.active);
    if (!tab)
        return { cwd: null, machine };
    if (focus?.space === space.id && focus?.tab === tab.id && focus?.terminal) {
        return { cwd: typeof focus.cwd === "string" && focus.cwd && !focus.cwd.includes("\uFFFD") ? focus.cwd : null, machine };
    }
    let cwd = null;
    for (const pane of panes) {
        if (pane.tab !== tab.id || !pane.terminal)
            continue;
        if (typeof pane.cwd !== "string" || !pane.cwd || pane.cwd.includes("\uFFFD") || (cwd && cwd !== pane.cwd))
            return { cwd: null, machine };
        cwd = pane.cwd;
    }
    return { cwd, machine };
}
