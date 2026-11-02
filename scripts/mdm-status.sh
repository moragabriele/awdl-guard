#!/bin/sh
# Inventory helper for MDM custom attributes / extension attributes.
# Prints one line: "<allowed|held-down> mode=<mode> version=<v>", "not-installed" or "not-running".
CTL=/usr/local/bin/awdl-guardctl

if [ ! -x "$CTL" ]; then
    echo "not-installed"
    exit 0
fi

json=$("$CTL" status --json 2>/dev/null) || { echo "not-running"; exit 0; }

field() { printf '%s' "$json" | plutil -extract "$1" raw -o - - 2>/dev/null; }

state=allowed
[ "$(field awdlAllowed)" = "false" ] && state=held-down
echo "$state mode=$(field mode) version=$(field version)"
