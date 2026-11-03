<p align="center">
  <img src="docs/icon.png" width="128" alt="AWDL Guard icon">
</p>

<h1 align="center">AWDL Guard</h1>

<p align="center">
  Stops AirDrop's radio from causing Wi-Fi lag on Macs, when it matters, as your MDM decides.
</p>

<p align="center">
  <a href="https://github.com/moragabriele/awdl-guard/releases/latest"><img src="https://img.shields.io/github/v/release/moragabriele/awdl-guard" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/signed-notarized-brightgreen" alt="Signed and notarized">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license"></a>
</p>

AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, Sidecar and Universal Control.
To do that, the Wi-Fi radio keeps leaving your access point's channel, and traffic waits:
latency spikes, choppy calls, sluggish browsing. macOS has no switch for it.

AWDL Guard holds AWDL down during calls and games (or always, or on a schedule) and gives it
back afterwards. In a [quick test](docs/benchmark.md):

| Gateway latency | AWDL allowed | AWDL held down |
|---|---:|---:|
| p95 | ~80 ms | 5.5 ms |
| Replies over 30 ms, per minute | 84–143 | 0 |

**Contents:** [Quick start](#quick-start) · [Modes](#modes) · [Configuration](#configuration) ·
[MDM deployment](#mdm-deployment) · [Privacy](#privacy) · [Building](#building)

## Quick start

1. Install `AWDLGuard-<version>.pkg` from the [latest release](https://github.com/moragabriele/awdl-guard/releases/latest).
2. That's it: a shield appears in the menu bar and AWDL is held down during calls and games.

```bash
awdl-guardctl status              # what it's doing and why
awdl-guardctl mode block          # always hold AWDL down (auto | block | allow | default)
awdl-guardctl allow 15            # AirDrop for 15 minutes
```

Uninstall: `sudo "/Library/Application Support/AWDL Guard/uninstall.sh"`

## Modes

- **`auto`** (default): AWDL is held down while the microphone is in use (any call app or
  browser), a game is in the foreground, or a listed app runs. It comes back 30 s after.
- **`block`**: always held down. Best latency, no AirDrop, AirPlay or Sidecar.
- **`allow`**: stock macOS.

Users switch mode from the menu bar or `awdl-guardctl mode`, unless the profile locks it.

**Schedule**: windows with a fixed mode, e.g. block on weekdays 09:00–18:00. Inside a window
it wins over everything else; windows may cross midnight; the first match wins.

```xml
<key>Schedule</key>
<array>
  <dict>
    <key>Days</key>  <array><string>mon</string><string>fri</string></array>  <!-- optional -->
    <key>Start</key> <string>09:00</string>
    <key>End</key>   <string>18:00</string>
    <key>Mode</key>  <string>block</string>
  </dict>
</array>
```

**Exclusions**: while an exempt app runs (e.g. one used with Sidecar), AWDL stays available,
even during a call. Set by the admin, or by users if allowed.

**Temporary allow**: from the menu bar, 5 minutes up to the admin's limit. A notification
one minute before it ends offers *Extend*.

**Wired Ethernet**: AWDL is left alone (`OnlyOnWiFi`). VPNs don't affect this.

**Emergency**: push a profile with `Mode` = `allow` and no `Schedule` (applied within 30 s), or
run `launchctl bootout system/io.github.moragabriele.awdlguard.daemon` as root, which restores
AWDL until the next restart.

While AWDL is held down, these don't work: AirDrop, peer-to-peer AirPlay, Sidecar, Universal
Control, iPhone Mirroring, wireless Continuity Camera, Apple Watch unlock.

## Configuration

Domain `io.github.moragabriele.awdlguard`. MDM profile > `/Library/Preferences` > defaults.
Changes apply within 30 s, or at once with `awdl-guardctl reload`.

| Key | Default | |
|---|---|---|
| `Mode` | `auto` | `auto`, `block`, `allow` |
| `AllowUserModeChange` | not set | not set: allowed unless the profile sets `Mode` |
| `Schedule` | `[]` | `Days`, `Start`, `End`, `Mode` |
| `TriggerOnMicrophone` | `true` | |
| `TriggerOnGames` | `true` | |
| `TriggerApps` | `[]` | bundle IDs, e.g. `us.zoom.xos` |
| `TriggerAppsMatch` | `running` | or `frontmost` |
| `ExemptApps` | `[]` | bundle IDs |
| `AllowUserExemptions` | `false` | users add their own from the menu |
| `OnlyOnWiFi` | `true` | |
| `ReenableDelaySeconds` | `30` | 0–3600 |
| `AllowUserOverride` | `true` | temporary allow from the menu |
| `OverrideMaxMinutes` | `15` | 1–1440 |
| `NotifyOnOverrideEnd` | `true` | |
| `NotifyOnSchedule` | `true` | |
| `NotifyOnAWDLChange` | `false` | every change; noisy |
| `ShowMenuBarIcon` | `true` | |
| `AllowUserQuit` | `true` | `false` hides *Quit* |

Without an MDM:

```bash
sudo defaults write /Library/Preferences/io.github.moragabriele.awdlguard Mode -string block
awdl-guardctl reload
```

## MDM deployment

Works with any MDM (Mosyle, Jamf, Kandji, Intune, …).

1. **Package**: the `.pkg` from the [releases](https://github.com/moragabriele/awdl-guard/releases).
2. **Profile**: [`profiles/AWDLGuard.mobileconfig`](profiles/AWDLGuard.mobileconfig) as a custom
   profile. It holds the settings and pre-approves background items and notifications, so users
   see no prompts and can't disable the background service. For different settings per group,
   duplicate it with new `PayloadIdentifier`/`PayloadUUID`s and scope one per Mac. If you sign
   your own builds, replace the Team ID `9WCXJSYTFT` in it.
   Jamf can use [`profiles/jamf-schema.json`](profiles/jamf-schema.json) for a settings form.
3. **Inventory**: [`scripts/mdm-status.sh`](scripts/mdm-status.sh) prints e.g.
   `held-down mode=auto version=0.3.1` for an extension attribute.
4. **Uninstall**: run the uninstall script above as root, then remove the profile.

## Privacy

Everything stays on the Mac. The microphone check only asks macOS *whether* an app is using
input, never records it, and needs no permission. The daemon accepts commands only from
binaries signed by the same Developer ID.

## Building

macOS 13+, Xcode Command Line Tools (Swift 5.10+).

```bash
make test        # unit tests
make pkg         # universal .pkg in dist/, ad-hoc signed (testing only)
make icon        # regenerate the app icon
```

Release: set `APP_IDENTITY`, `PKG_IDENTITY` and `NOTARY_PROFILE` (see
[`packaging/build.sh`](packaging/build.sh)). Measure your own network with
[`scripts/latency-bench.sh`](scripts/latency-bench.sh). Logs:

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.moragabriele.awdlguard"'
```

Tip: putting the access point's 5 GHz channel on 44 or 149 (AWDL channels) reduces the
hopping, but doesn't remove it.

## License

MIT. Built on [AWDLControl](https://github.com/james-howard/AWDLControl) by James Howard (MIT).
