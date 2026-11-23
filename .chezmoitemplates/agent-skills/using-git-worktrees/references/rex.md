# Rex PR Review

Launch only when handling a new `pr-review` skill invocation in a verified local Rex block.
Do not select a session by UI focus. Read `rex` and match `REX_SESSION` and `REX_BLOCK` against
`rex whoami --json`. No remote host, automatic server start or fallback.

1. Select the runtime using `~/.agents/AGENTS.md`. The fixed-checkout Rex review currently
   validates OMP. If a different runtime was explicitly requested, report that it is unsupported
   here rather than silently launching OMP or a legacy adapter.
2. Prepare only: `node "$HOME/.local/share/pr-review/runtime.js" prepare-rex --environment rex --no-focus --skill-file "$rendered_skill" "$pr"`.
   Use the absolute path of the trusted deployed `pr-review` skill as `rendered_skill`. Add `--quick`
   or `--repo-path` when requested. Require `status: prepared`. Worktrunk owns the fixed-base
   checkout. Use the returned `checkout.path`, `artifactPath`, `agentName` and `launchContextFile`.
3. Start one background tab. Use the checkout path as `base`, the artifact directory as `run`,
   and the returned label as `name`. Resolve `omp` to its absolute executable with `which`.

   ```sh
   rex --autostart=false run -s "$REX_SESSION" -c "$base" --shell=none --focus=false --keep-open --json --label "$name" -- \
     /bin/sh -c 'umask 077; exec /usr/bin/env PI_PROGRAM_STATUS=1 "$@"' sh "$omp" \
     --cwd "$base" --session-dir "$run/sessions" --config "$run/omp-config.yml" \
     --no-extensions --no-skills --no-context-files --no-rules --no-title
   ```

4. Record the returned block ID as `block`. Observe the same block with `program_status`; wait
   for the OMP process to be idle without answering permission prompts. Then run
   `node "$run/runtime.js" bind-rex-reviewer "$launchContextFile" "$block"`. Require
   `status: ready`; the helper rechecks the fixed revision, checkout and live reviewer identity.
5. In that exact verified block, submit one instruction to read `$run/SKILL.md`, validate the
   returned `contextFile` with the run-local runtime, and execute the prepared-review contract.
   Use the verified Rex handoff procedure from `agent-communication`; do not resend on uncertainty.
   Record the queued request separately from reviewer acceptance or validated start.

Run-local OMP options disable auto-resume, unattended setup, startup updates, automatic task
suggestions and project MCP discovery. They do not disable the user's global MCP servers or
provide an OS sandbox. Never execute PR-head code or load its configuration.

For bounded observation of the same reviewer, inspect the recorded block with
`rex block call -s SESSION -b BLOCK program_status` and capture its report with
`rex capture -s SESSION -b BLOCK --trim`. Verify the matching private start and result
artifacts. If a status or delivery is uncertain, retain the block and checkout; do not resend,
replace or switch hosts. Never run the prepared validator outside the recorded reviewer.
