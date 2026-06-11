#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WakeKeeper"
BUNDLE_ID="local.ben.WakeKeeper"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

can_toggle_disablesleep_without_password() {
  sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1 &&
    sudo -n -l /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 &&
    sudo -n -l /usr/bin/pmset -b disablesleep 1 >/dev/null 2>&1 &&
    sudo -n -l /usr/bin/pmset -b disablesleep 0 >/dev/null 2>&1 &&
    sudo -n -l /usr/bin/pmset -c disablesleep 1 >/dev/null 2>&1 &&
    sudo -n -l /usr/bin/pmset -c disablesleep 0 >/dev/null 2>&1
}

ensure_passwordless_pmset() {
  if [[ "${WAKEKEEPER_SKIP_SUDOERS_SETUP:-}" == "1" ]]; then
    return
  fi

  if can_toggle_disablesleep_without_password; then
    return
  fi

  echo "WakeKeeper needs one-time sudoers setup before it can toggle sleep without prompting."
  echo "Installing /etc/sudoers.d/wakekeeper now; macOS may ask for your administrator password once."
  ./scripts/install-sudoers.sh
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

ensure_passwordless_pmset
./scripts/build-app.sh

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
