import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex, Progress, ProgressTrack, ProgressIndicator } from "gpui-base";
import { exec, theme, props, openOverlay, closeOverlay, shared, setShared, run, nextCommand, settings } from "herdr";
import { parseUsage } from "./usage.js";

const REFRESH_MS = 300000;
const STATE = "workbench.usage";
// Provider labels can contain account identifiers. Persist only known quota labels.
const LABELS = new Set(["5 hours", "7 days", "24 hours", "30 days", "session", "daily", "weekly", "monthly", "primary", "secondary", "spend cap"]);
function safeLabel(label, index) {
  const normalized = label.trim().toLowerCase().replace(/\s+/g, " ");
  return LABELS.has(normalized) ? normalized : `Limit ${index + 1}`;
}
function safeProvider(provider) {
  return /^[a-z][a-z0-9-]{0,32}$/.test(provider) ? provider : "provider";
}
function percent(value) {
  return `${Math.round(value * 100) / 100}%`;
}
function resetTime(value) {
  if (value === null) return "";
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? ` · resets ${date.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, " UTC")}` : "";
}
function localResetTime(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return "";
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "";
  const pad = number => String(number).padStart(2, "0");
  return `↻ ${pad(date.getMonth() + 1)}/${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}


const USAGE_ARGS = ["usage", "--json", "--redact", "--no-extensions"];
// OMP config commands also create databases. Inspect paths before running OMP.
// These are OMP's profile and XDG data-directory rules; only directory metadata is read.
const PROFILE_SCAN = [
  '[ -n "${HOME-}" ] || exit 1',
  'root="$HOME/${PI_CONFIG_DIR:-.omp}"',
  'if [ "${OMP_PROFILE+x}" = x ]; then active="$OMP_PROFILE"; else active="${PI_PROFILE-}"; fi',
  'active="${active#"${active%%[![:space:]]*}"}"; active="${active%"${active##*[![:space:]]}"}"',
  'case "$active" in ""|default) active="" ;; [a-z0-9]*) case "$active" in *[!a-z0-9._-]*|*.) exit 2 ;; esac ;; *) exit 2 ;; esac',
  'printf "A%s\\0" "$active"',
  'xdg=""',
  'if [ -n "${XDG_DATA_HOME-}" ]; then',
  '  command -v uname >/dev/null 2>&1 || exit 3',
  '  case "$(uname -s)" in Darwin|Linux) xdg="${XDG_DATA_HOME%/}/omp" ;; esac',
  'fi',
  'legacy="${PI_PROFILE-}"; legacy="${legacy#"${legacy%%[![:space:]]*}"}"; legacy="${legacy%"${legacy##*[![:space:]]}"}"',
  'case "$legacy" in ""|default|.*|*[!a-z0-9._-]*|*.) legacy="" ;; esac',
  'case "$legacy" in con|con.*|prn|prn.*|aux|aux.*|nul|nul.*|com[0-9]|com[0-9].*|lpt[0-9]|lpt[0-9].*) legacy="" ;; esac',
  '[ "${#legacy}" -le 64 ] || legacy=""',
  'agent="${PI_CODING_AGENT_DIR:-$root/agent}"',
  'if [ -n "$legacy" ] && [ "$agent" = "$root/profiles/$legacy/agent" ]; then agent="$root/agent"; fi',
  'defaultdb="$agent/agent.db"',
  'if [ "$agent" = "$root/agent" ] && [ -n "$xdg" ] && [ -d "$xdg" ]; then defaultdb="$xdg/agent.db"; fi',
  'check_default=1',
  'if [ -n "${PI_CODING_AGENT_DIR-}" ] && [ -n "$xdg" ] && [ -d "$xdg" ]; then',
  '  case "$PI_CODING_AGENT_DIR" in /*) ;; *) check_default=0 ;; esac',
  '  case "$PI_CODING_AGENT_DIR" in */|*//*|*/./*|*/../*|*/.|*/..) check_default=0 ;; esac',
  '  case "$root" in */|*//*|*/./*|*/../*|*/.|*/..) check_default=0 ;; esac',
  'fi',
  'if [ "$check_default" = 0 ]; then printf "C\\0"; elif [ -f "$defaultdb" ]; then printf "D\\0"; fi',
  'for parent in "$root/profiles" "${xdg:+$xdg/profiles}"; do',
  '  [ -n "$parent" ] || continue',
  '  if [ -d "$parent" ] && { [ ! -r "$parent" ] || [ ! -x "$parent" ]; }; then printf "W\\0"; continue; fi',
  '  for d in "$parent"/*; do',
  '    [ -d "$d" ] || continue',
  '    name="${d##*/}"',
  '    case "$name" in ""|default|.*|*[!a-z0-9._-]*|*.) continue ;; [a-z0-9]*) ;; *) continue ;; esac',
  '    db="$root/profiles/$name/agent/agent.db"',
  '    if [ -n "$xdg" ] && [ -d "$xdg/profiles/$name" ]; then db="$xdg/profiles/$name/agent.db"; fi',
  '    [ ! -f "$db" ] || printf "P%s\\0" "$name"',
  '  done',
  'done',
  'exit 0',
].join("\n");
const safeProfile = name => String(name).replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 64) || "unnamed";
const profileLabel = name => name === null ? "default" : `profile ${safeProfile(name)}`;
const validProfile = name => /^[a-z0-9][a-z0-9._-]{0,63}$/.test(name) && !name.endsWith(".")
  && !/^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(name);
const NAMED_WINDOWS = new Set(["5 hours", "7 days", "24 hours", "30 days", "daily", "weekly", "monthly", "session"]);
const reportLabel = row => {
  if (!row.window) return row.label;
  return !row.label || NAMED_WINDOWS.has(row.label) ? row.window : `${row.window} · ${row.label}`;
};
const unavailable = row => row.label || row.window ? `${reportLabel(row)} · unavailable` : "Usage unavailable";

async function usageProfiles() {
  let scan;
  try {
    const result = await exec("sh", ["-c", PROFILE_SCAN]);
    if (result.code === 0) scan = result.stdout.split("\0");
  } catch {}
  const activeRecord = scan?.find(record => record.startsWith("A"));
  if (!activeRecord || (activeRecord.length > 1 && !validProfile(activeRecord.slice(1)))) return { sources: [], notices: ["OMP profile discovery error. POSIX sh and a valid profile are required."] };
  const active = activeRecord.slice(1) || null, names = new Set();
  if (scan.includes("D")) names.add(null);
  for (const record of scan) if (record.startsWith("P") && validProfile(record.slice(1))) names.add(record.slice(1));
  const notices = [];
  if (scan.includes("W")) notices.push("OMP profile directory is not readable.");
  if (scan.includes("C")) notices.push("Default OMP profile path could not be identified safely.");
  if (!names.has(active)) notices.push(`${profileLabel(active)} · unavailable`);
  const sources = [...names].map(name => ({ name, label: profileLabel(name), current: name === active }));
  return { sources, notices };
}

function progress(row, id, t) {
  const value = Math.max(0, Math.min(100, row.usedPercent));
  const color = row.status === "exhausted" ? t.blocked : row.status === "warning" ? t.working : t.accent;
  return Progress.new(id).flex_1().min_w(24).value(value)
    .child(ProgressTrack.new().w_full().h(4).rounded_full().bg(t.border)
      .child(ProgressIndicator.new().h_full().w(`${value}%`).rounded_full().bg(color)));
}

export default class WorkbenchUsage extends View {
  init(_props, cx) {
    const mode = props()?.mode;
    if (mode === "compact" || mode === "sidebar") {
      this.refresh(cx, true);
      cx.timer.every(REFRESH_MS, (taskCx) => this.refresh(taskCx));
      cx.spawn(async (taskCx) => {
        for (;;) if (await nextCommand() === "refresh") this.refresh(taskCx);
      });
    } else if (!shared(STATE)) {
      this.refresh(cx);
    }
  }

  refresh(cx, force = false) {
    if (!force && shared(STATE)?.loading) return;
    const request = `${Date.now()}-${Math.random()}`;
    this.request = request;
    setShared(STATE, { ...(shared(STATE) ?? {}), request, loading: true, error: null });
    cx.spawn(async (taskCx) => {
      const rows = [];
      const { sources, notices } = await usageProfiles();
      let failures = 0;
      for (const [sourceIndex, source] of sources.entries()) {
        if (shared(STATE)?.request !== request) return;
        try {
          const command = source.current ? "omp" : "env";
          const args = source.current ? USAGE_ARGS : [`OMP_PROFILE=${source.name ?? "default"}`, "omp", ...USAGE_ARGS];
          const result = await exec(command, args);
          if (result.code !== 0) throw new Error("usage failed");
          const parsed = parseUsage(result.stdout), accounts = new Map();
          if (!parsed.length) notices.push(`${source.label} · unavailable`);
          for (const [index, row] of parsed.entries()) {
            const key = `${row.provider}\0${row.account}`;
            if (!accounts.has(key)) accounts.set(key, accounts.size);
            rows.push({
              profile: source.label, profileKey: sourceIndex, accountKey: accounts.get(key),
              provider: safeProvider(row.provider), label: row.label ? safeLabel(row.label, index) : "",
              usedPercent: row.usedPercent, resetsAt: row.resetsAt, status: row.status,
              window: row.window, account: row.account, accounts: row.accounts,
            });
          }
        } catch {
          failures++;
          notices.push(`${source.label} · error`);
        }
      }
      const error = failures && !rows.length ? "OMP usage error. Check authentication and the app's PATH." : null;
      if (shared(STATE)?.request !== request) return;
      this.request = null;
      setShared(STATE, { rows, notices, error, loading: false, loaded: true });
      taskCx.notify();
    });
  }

  async close() {
    const state = shared(STATE);
    if (this.request && state?.request === this.request) {
      setShared(STATE, { ...state, request: null, loading: false, error: "Refresh interrupted. Retry to update usage." });
      run("workbench-usage.refresh");
    }
  }

  render() {
    const t = theme();
    const mode = props()?.mode;
    const { rows = [], notices = [], loading = false, error = null, loaded = false } = shared(STATE) ?? {};
    const button = (id, text, action) => div().id(id).px(8).py(3).cursor_pointer()
      .text_color(t.muted).hover(s => s.text_color(t.foreground)).on_click(action).child(text);
    const groups = [], byAccount = new Map();
    for (const row of rows) {
      const key = `${row.profileKey ?? row.profile ?? "current"}:${row.accountKey ?? `${row.provider}:${row.account ?? 1}`}`;
      if (!byAccount.has(key)) {
        const group = { profile: row.profile ?? "current", provider: row.provider, account: row.account, accounts: row.accounts, rows: [] };
        byAccount.set(key, group); groups.push(group);
      }
      byAccount.get(key).rows.push(row);
    }
    const title = group => `${group.provider}${group.accounts > 1 ? ` #${group.account}` : ""}`;
    const parts = groups.flatMap(group => group.rows.map(row => {
      const label = [`OMP ${group.profile}`, title(group), reportLabel(row), Number.isFinite(row.usedPercent) ? percent(row.usedPercent) : "unavailable"].filter(Boolean).join(" · ");
      return { label, reset: resetTime(row.resetsAt) };
    }));
    const prefix = [...(error ? ["error"] : []), ...notices];
    const summary = loading ? "loading…" : [...prefix, ...parts.map(part => part.label)].join(" · ") || "unavailable";
    const resetSummary = loading ? summary : [...prefix, ...parts.map(part => `${part.label}${part.reset}`)].join(" · ") || "unavailable";
    const openDetails = () => openOverlay({ mod: "workbench-usage", kind: "dialog", width: 620, height: 440, props: { mode: "detail" } });
    if (mode === "sidebar") {
      return v_flex().id("usage-open").size_full().min_w(0).min_h(0).px(8).py(5).gap(3).bg(t.chrome).border_t(1).border_color(t.border)
        .on_size_change((size, cx) => {
          const zoom = settings().zoom;
          const narrow = size.width / (typeof zoom === "number" && zoom > 0 ? zoom : 1) < 160;
          if (narrow !== this.narrow) { this.narrow = narrow; cx.notify(); }
        })
        .tooltip(`OMP account usage: ${resetSummary}`).cursor_pointer().on_click(openDetails)
        .child(h_flex().flex_none().items_center().gap(6).text_size(11).text_color(t.muted)
          .child(svg("icons/agent.svg").size(13).flex_none())
          .when(!this.narrow, el => el.child(div().flex_1().min_w(0).truncate().child(loading ? "Usage · loading…" : "Usage")))
          .when(!this.narrow, el => el.child(button("usage-refresh", "↻", (_e, cx) => { cx.stop_propagation(); this.refresh(cx, true); }).tooltip("Refresh usage"))))
        .when(!this.narrow, el => el.child(v_flex().id("usage-sidebar-list").flex_1().min_h(0).gap(7).overflow_y_scrollbar()
          .when(Boolean(error), list => list.child(div().text_size(10.5).text_color(t.blocked).child(error)))
          .when(!error && !loading && !rows.length && !notices.length, list => list.child(div().text_size(10.5).text_color(t.muted).child("Usage unavailable")))
          .children(notices.map(notice => div().text_size(10.5).text_color(notice.includes("error") ? t.blocked : t.dim).child(notice)))
          .children(groups.map((group, groupIndex) => v_flex().gap(3)
            .child(h_flex().items_center().gap(6).text_size(10.5)
              .tooltip(group.accounts > 1 ? `Anonymous account #${group.account} in reported order` : `OMP · ${group.profile}`)
              .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(title(group)))
              .child(div().min_w(0).truncate().text_color(t.dim).child(`OMP · ${group.profile}`)))
            .children(group.rows.map((row, rowIndex) => {
              const reset = localResetTime(row.resetsAt);
              const resetLine = () => div().text_size(10).text_color(t.muted).tooltip(`Reset time (local)${resetTime(row.resetsAt)}`).child(reset);
              return Number.isFinite(row.usedPercent)
                ? h_flex().items_center().gap(5).text_size(10).text_color(t.muted)
                  .child(v_flex().w(70).flex_none().min_w(0)
                    .child(div().truncate().child(reportLabel(row)))
                    .when(Boolean(reset), el => el.child(resetLine())))
                  .child(progress(row, `usage-sidebar-${groupIndex}-${rowIndex}`, t))
                  .child(div().w(38).flex_none().child(percent(row.usedPercent)))
                : v_flex().text_size(10).text_color(t.dim).child(unavailable(row))
                  .when(Boolean(reset), el => el.child(resetLine()));
            }))))));
    }
    if (mode === "compact") {
      return h_flex().size_full().min_w(0).items_center().text_size(11).text_color(t.muted)
        .child(div().id("usage-open").flex_1().min_w(0).truncate().cursor_pointer().tooltip(`OMP account usage: ${summary}`)
          .on_click(openDetails)
          .child(`OMP account usage: ${summary}`))
        .child(button("usage-refresh", "↻", (_e, cx) => this.refresh(cx, true)));
    }
    return v_flex().size_full().min_h(0).p(16).gap(10).bg(t.popover).text_size(12).text_color(t.foreground)
      .child(h_flex().items_center().gap(8)
        .child(div().flex_1().text_size(15).font_semibold().child("OMP account usage"))
        .child(button("usage-refresh", loading ? "Refreshing…" : "Refresh", (_e, cx) => this.refresh(cx, true)))
        .child(button("usage-close", "Close", () => closeOverlay(props().overlay))))
      .child(div().text_color(t.dim).child("OMP-reported account limits by profile; not spending or direct Claude Code usage."))
      .child(v_flex().id("usage-list").flex_1().min_h(0).gap(8).overflow_y_scrollbar()
        .when(Boolean(error), el => el.child(div().text_color(t.foreground).child(error)))
        .when(!error && loading && !loaded, el => el.child(div().text_color(t.muted).child("Loading usage…")))
        .when(!error && loaded && !rows.length && !notices.length, el => el.child(div().text_color(t.muted).child("Usage unavailable: no usable limits reported.")))
        .children(notices.map(notice => div().text_color(notice.includes("error") ? t.blocked : t.dim).child(notice)))
        .children(groups.map((group, groupIndex) => v_flex().gap(6).p(10).bg(t.raised)
          .child(h_flex().gap(8)
            .child(div().flex_1().child(title(group)))
            .child(div().text_color(t.dim).child(`OMP · ${group.profile}`)))
          .when(group.accounts > 1, el => el.child(div().text_color(t.dim).child("Anonymous account number in reported order")))
          .children(group.rows.map((row, rowIndex) => Number.isFinite(row.usedPercent)
            ? v_flex().gap(3)
              .child(h_flex().items_center().gap(8)
                .child(div().w(110).child(reportLabel(row)))
                .child(progress(row, `usage-detail-${groupIndex}-${rowIndex}`, t))
                .child(div().child(`${percent(row.usedPercent)} used`)))
              .child(div().text_color(t.dim).child(`${row.status && row.status !== "unknown" ? row.status : "Reported"}${resetTime(row.resetsAt)}`))
            : div().text_color(t.dim).child(unavailable(row)))))));
  }
}
