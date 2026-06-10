# WakeKeeper Instructions

- Keep README.md and AGENTS.md in sync when changing project behavior, build steps, or operational caveats.
- Follow TDD for power-setting behavior: test command construction and parsing in `WakeKeeperCore` instead of duplicating implementation logic in tests.
- Do not run `pmset` mutations in automated tests. Tests should verify the commands that would be run.
- The app must restore normal sleep settings on toggle-off and normal quit.
