import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

export default function (pi: ExtensionAPI) {
  let timer: ReturnType<typeof setInterval> | undefined;

  pi.on('session_start', (_event, ctx) => {
    // Orca owns its title markers and spinner when running inside an Orca pane.
    if (ctx.mode !== 'tui' || process.env.ORCA_PANE_KEY) return;
    const paint = () => {
      try {
        const session = pi.getSessionName();
        ctx.ui.setTitle(session || 'pi');
      } catch {
        if (timer) clearInterval(timer);
        timer = undefined;
      }
    };
    paint();
    // Pi can restore its own title after session changes and other UI events.
    timer = setInterval(paint, 1000);
    timer.unref();
  });

  pi.on('session_shutdown', () => {
    if (timer) clearInterval(timer);
    timer = undefined;
  });
}
