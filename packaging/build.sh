#!/bin/bash
# Builds a universal installer package.
#
# Unsigned (local testing):   ./packaging/build.sh
# Release:
#   APP_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
#   PKG_IDENTITY="Developer ID Installer: <Name> (<TEAMID>)" \
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`> \
#   ./packaging/build.sh
#
# No secrets live in this repo: identities come from the keychain, notary credentials
# from a notarytool keychain profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "$ROOT/Sources/AWDLShared/Constants.swift")"
DAEMON=io.github.moragabriele.awdlguard.daemon
AGENT=io.github.moragabriele.awdlguard.agent
PKG_ID=io.github.moragabriele.awdlguard.pkg
APP_NAME="AWDL Guard.app"

OUT="$ROOT/dist"
WORK="$ROOT/.build/pkg"
PAYLOAD="$WORK/payload"
rm -rf "$WORK"
mkdir -p "$PAYLOAD" "$OUT"

echo "==> Building $VERSION (arm64 + x86_64)"
for arch in arm64 x86_64; do
    swift build --package-path "$ROOT" -c release --arch "$arch" --scratch-path "$ROOT/.build/$arch"
done
BIN_ARM="$(swift build --package-path "$ROOT" -c release --arch arm64 --scratch-path "$ROOT/.build/arm64" --show-bin-path)"
BIN_X86="$(swift build --package-path "$ROOT" -c release --arch x86_64 --scratch-path "$ROOT/.build/x86_64" --show-bin-path)"

universal() { # <product> <destination>
    mkdir -p "$(dirname "$2")"
    lipo -create "$BIN_ARM/$1" "$BIN_X86/$1" -output "$2"
}

echo "==> Assembling payload"
APP="$PAYLOAD/Applications/$APP_NAME"
mkdir -p "$APP/Contents/MacOS"
universal AWDLGuardAgent "$APP/Contents/MacOS/AWDLGuardAgent"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Agent-Info.plist" > "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cat "$ROOT/Resources/AppIcon.icns" > "$APP/Contents/Resources/AppIcon.icns"

universal awdl-guardd "$PAYLOAD/Library/PrivilegedHelperTools/$DAEMON"
universal awdl-guardctl "$PAYLOAD/usr/local/bin/awdl-guardctl"

mkdir -p "$PAYLOAD/Library/LaunchDaemons" "$PAYLOAD/Library/LaunchAgents" \
         "$PAYLOAD/Library/Application Support/AWDL Guard"
# Copy content only: extended attributes (some, like com.apple.macl, can't be stripped)
# would end up in the package as ._ AppleDouble files.
copy() { cat "$1" > "$2"; }
copy "$ROOT/Resources/LaunchDaemon.plist" "$PAYLOAD/Library/LaunchDaemons/$DAEMON.plist"
copy "$ROOT/Resources/LaunchAgent.plist" "$PAYLOAD/Library/LaunchAgents/$AGENT.plist"
copy "$ROOT/packaging/uninstall.sh" "$PAYLOAD/Library/Application Support/AWDL Guard/uninstall.sh"
copy "$ROOT/LICENSE" "$PAYLOAD/Library/Application Support/AWDL Guard/LICENSE"
chmod 755 "$PAYLOAD/Library/Application Support/AWDL Guard/uninstall.sh"

echo "==> Code signing"
if [ -n "${APP_IDENTITY:-}" ]; then
    SIGN=(codesign --force --options runtime --timestamp --sign "$APP_IDENTITY")
else
    echo "    APP_IDENTITY not set: ad-hoc signing (local testing only, cannot be notarized)"
    SIGN=(codesign --force --options runtime --sign -)
fi
"${SIGN[@]}" --identifier "$DAEMON" "$PAYLOAD/Library/PrivilegedHelperTools/$DAEMON"
"${SIGN[@]}" --identifier io.github.moragabriele.awdlguard.ctl "$PAYLOAD/usr/local/bin/awdl-guardctl"
"${SIGN[@]}" "$APP"

echo "==> Building package"
pkgbuild --analyze --root "$PAYLOAD" "$WORK/components.plist" >/dev/null
# Install exactly at /Applications, never "upgrade" a copy found elsewhere on disk.
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
chmod 755 "$ROOT/packaging/scripts/"*
pkgbuild --root "$PAYLOAD" --component-plist "$WORK/components.plist" \
    --scripts "$ROOT/packaging/scripts" --identifier "$PKG_ID" --version "$VERSION" \
    --install-location / "$WORK/component.pkg"

PKG="$OUT/AWDLGuard-$VERSION.pkg"
if [ -n "${PKG_IDENTITY:-}" ]; then
    # Timestamped, so the package stays valid after the certificate expires.
    productbuild --package "$WORK/component.pkg" --sign "$PKG_IDENTITY" --timestamp "$PKG"
else
    productbuild --package "$WORK/component.pkg" "$PKG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
fi

echo "==> Done: $PKG"
