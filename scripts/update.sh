#!/bin/sh
# Updates AWDL Guard to the latest GitHub release. Run as root, e.g. as a scheduled MDM
# custom command. Does nothing if AWDL Guard isn't installed or is already up to date.
# Installs only a package signed by the expected Developer ID team and notarized by Apple.
set -u

REPO=moragabriele/awdl-guard
TEAM_ID=9WCXJSYTFT
PKG_ID=io.github.moragabriele.awdlguard.pkg

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root"
    exit 1
fi

installed=$(pkgutil --pkg-info "$PKG_ID" 2>/dev/null | sed -n 's/^version: //p')
if [ -z "$installed" ]; then
    echo "not-installed: nothing to update"
    exit 0
fi

# /releases/latest redirects to /releases/tag/v<version>.
url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") || {
    echo "error: can't reach GitHub"
    exit 1
}
latest=${url##*/v}
case "$latest" in
    [0-9]*.[0-9]*) ;;
    *) echo "error: unexpected release URL $url"; exit 1 ;;
esac

newest=$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n 1)
if [ "$installed" = "$latest" ] || [ "$newest" = "$installed" ]; then
    echo "up-to-date: $installed"
    exit 0
fi

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
pkg="$tmp/AWDLGuard.pkg"

echo "updating: $installed -> $latest"
curl -fsSL -o "$pkg" "https://github.com/$REPO/releases/download/v$latest/AWDLGuard-$latest.pkg" || {
    echo "error: download failed"
    exit 1
}

# The leaf certificate must be our Developer ID Installer certificate.
signer=$(pkgutil --check-signature "$pkg" | sed -n 's/^ *1\. //p')
case "$signer" in
    "Developer ID Installer: "*"($TEAM_ID)") ;;
    *) echo "error: unexpected signer: ${signer:-unsigned}"; exit 1 ;;
esac
if ! spctl --assess --type install "$pkg" 2>/dev/null; then
    echo "error: package not accepted by Gatekeeper (not notarized?)"
    exit 1
fi

installer -pkg "$pkg" -target / >/dev/null || {
    echo "error: installer failed"
    exit 1
}
echo "updated: $(pkgutil --pkg-info "$PKG_ID" | sed -n 's/^version: //p')"
