# WakeKeeper

WakeKeeper is a small macOS menu bar utility for keeping local agents alive on a laptop.

When you turn it on, it does two things:

- Starts `/usr/bin/caffeinate -dimsu` to prevent idle, display, disk, and system sleep.
- Runs `/usr/bin/pmset -a disablesleep 1` with administrator approval so macOS will not enter normal sleep and drop Wi-Fi.

When you turn it off or quit normally, it stops `caffeinate` and restores the previous `disablesleep` setting. If the app is force-quit or the Mac restarts while awake mode is on, launch WakeKeeper again and choose **Restore Normal Sleep** from the menu.

## Build

```sh
swift test
./scripts/build-app.sh
open build/WakeKeeper.app
```

The first time you turn WakeKeeper on or off, macOS asks for an administrator password because `pmset` changes system power settings.

## Notes

- This intentionally does not install a launch agent or background helper.
- Closing a MacBook lid may still behave differently depending on hardware, power adapter, and external display state. WakeKeeper is aimed at keeping agents running while the laptop is open but unattended.
- To inspect the current power settings manually, run `pmset -g custom`.
