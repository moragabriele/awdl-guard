#!/bin/sh
# Removes AWDL Guard. Run as root (e.g. from an MDM script).
# The daemon restores awdl0 when it is stopped, so AirDrop & co. work again immediately.
set -u

DAEMON=io.github.moragabriele.awdlguard.daemon
AGENT=io.github.moragabriele.awdlguard.agent
PKG_ID=io.github.moragabriele.awdlguard.pkg

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

for uid in $(ps -axo uid=,comm= | awk '/AWDLGuardAgent$/ {print $1}' | sort -u); do
    launchctl bootout "gui/$uid/$AGENT" 2>/dev/null || true
done
pkill -x AWDLGuardAgent 2>/dev/null || true
launchctl bootout "system/$DAEMON" 2>/dev/null || true

rm -f "/Library/LaunchDaemons/$DAEMON.plist" \
      "/Library/LaunchAgents/$AGENT.plist" \
      "/Library/PrivilegedHelperTools/$DAEMON" \
      /usr/local/bin/awdl-guardctl
rm -rf "/Applications/AWDL Guard.app" "/Library/Application Support/AWDL Guard"

# Make sure AWDL is back even if the daemon was not running.
ifconfig awdl0 up 2>/dev/null || true

pkgutil --forget "$PKG_ID" >/dev/null 2>&1 || true
echo "AWDL Guard removed. Configuration profiles must be removed from your MDM."
