# WakeKeeper

WakeKeeper is a small macOS menu bar utility for keeping local agents alive on a laptop.

When you turn it on, it does two things:

- Starts `/usr/bin/caffeinate -dimsu` to prevent idle, display, disk, and system sleep.
- Runs `/usr/bin/pmset -a disablesleep 1` through a narrow passwordless sudoers rule so macOS will not enter normal sleep and drop Wi-Fi.

When you turn it off or quit normally, it restores the previous `disablesleep` setting and stops `caffeinate`. If the app is force-quit or the Mac restarts while awake mode is on, launch WakeKeeper again; it will show that restoration is needed, and you can either choose **Restore Normal Sleep** or quit normally to restore the saved setting.

## Build

```sh
swift test
./script/build_and_run.sh
./scripts/build-app.sh
open build/WakeKeeper.app
```

Use `./script/build_and_run.sh` during development so any stale WakeKeeper process is stopped before the current source is rebuilt and launched. `./scripts/build-app.sh` only builds the bundle.

The run script also checks the one-time sudoers setup and installs it when missing, so development usually starts with just `./script/build_and_run.sh`. Set `WAKEKEEPER_SKIP_SUDOERS_SETUP=1` if you only want to rebuild and launch without touching `/etc/sudoers.d`.

## One-Time Passwordless Setup

`pmset` needs root privileges to change `disablesleep`. To avoid an administrator password prompt every time you toggle WakeKeeper, install the sudoers rule once. The development run script does this automatically when needed, or you can run it directly:

```sh
./scripts/install-sudoers.sh
```

The installer writes the rule for the current user, or for the original `SUDO_USER` when run through `sudo`, and refuses unexpected user names before validating the file with `visudo`.

The rule allows your user to run only these commands without a password:

- `/usr/bin/pmset -a disablesleep 1`
- `/usr/bin/pmset -a disablesleep 0`
- `/usr/bin/pmset -b disablesleep 1`
- `/usr/bin/pmset -b disablesleep 0`
- `/usr/bin/pmset -c disablesleep 1`
- `/usr/bin/pmset -c disablesleep 0`

To remove the rule:

```sh
./scripts/uninstall-sudoers.sh
```

## Notes

- This intentionally does not install a launch agent or background helper.
- Closing a MacBook lid may still behave differently depending on hardware, power adapter, and external display state. WakeKeeper is aimed at keeping agents running while the laptop is open but unattended.
- To inspect the current power settings manually, run `pmset -g custom`.
