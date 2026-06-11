# WakeKeeper Instructions

- Keep README.md and AGENTS.md in sync when changing project behavior, build steps, or operational caveats.
- Use `./script/build_and_run.sh` for local run loops so stale WakeKeeper processes are stopped before rebuilding and launching the current bundle. The run script may perform the one-time sudoers setup unless `WAKEKEEPER_SKIP_SUDOERS_SETUP=1` is set.
- Follow TDD for power-setting behavior: test command construction and parsing in `WakeKeeperCore` instead of duplicating implementation logic in tests.
- Do not run `pmset` mutations in automated tests. Tests should verify the commands that would be run.
- The app must restore normal sleep settings on toggle-off and normal quit.
- A saved power-settings snapshot is pending restoration even if the app-owned `caffeinate` process is no longer running after relaunch or failure.
- Passwordless operation uses `/etc/sudoers.d/wakekeeper` and must stay limited to the exact `pmset disablesleep` commands documented in README.md.
