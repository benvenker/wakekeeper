#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$(id -un)}"
SUDOERS_FILE="/etc/sudoers.d/wakekeeper"
TMP_FILE="$(mktemp)"

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT

cat >"$TMP_FILE" <<EOF
# WakeKeeper: allow ${USER_NAME} to toggle only macOS disablesleep without a password.
${USER_NAME} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -b disablesleep 1, /usr/bin/pmset -b disablesleep 0, /usr/bin/pmset -c disablesleep 1, /usr/bin/pmset -c disablesleep 0
EOF

chmod 0440 "$TMP_FILE"
sudo chown root:wheel "$TMP_FILE"
sudo visudo -cf "$TMP_FILE"
sudo install -m 0440 -o root -g wheel "$TMP_FILE" "$SUDOERS_FILE"

echo "Installed $SUDOERS_FILE for ${USER_NAME}."
echo "WakeKeeper can now toggle disablesleep without showing a password prompt."
