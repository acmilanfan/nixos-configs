# macOS upgrade preparation

Preparation for macOS 27.2, checked on mac-home running macOS 26.7 on
2026-10-28. This is not a claim that the complete setup has been tested on 27.2.
Installed versions on mac-work must be checked separately.

## Prepared change

`nixos/common/home-darwin.nix` selects a local wrapper around
`unstable.sketchybar` for both Macs. The existing locked unstable input supplies
2.24.1; `nixos/common/pkgs/sketchybar/` adds the exact tested menu-coordination
patch. No input update or second Homebrew installation is required.

SketchyBar's [macOS 27 tracking issue][sketchybar] describes a window-stack bug:
clicking empty bar areas can obscure the items. Upstream merged a fix and users
report success with 2.24.1, although another report with that version remained.
Retest with this configuration; a version number alone does not prove the bug
is absent. The change is effective only after a reviewed rebuild and bar restart.

Do not run a full `sup` just to test this package when unrelated changes are
pending. Activation also runs Homebrew upgrades and keyboard initialization;
it is not an isolated SketchyBar update. Preparation builds/evaluations do not
activate the configuration or replace the currently running bar.

## Keyboard: preserve the working combination

Observed on mac-home:

| Component | Version |
| --- | --- |
| `/usr/local/bin/kanata-nix` | 1.12.0 |
| Karabiner-Elements | 15.9.0 |
| VirtualHIDDevice package/daemon | 6.8.0 |
| Activated DriverKit extension | 1.8.0 |

The package and extension have different version numbers; do not compare them
as if they were the same component.

The [Kanata 1.12 release instructions][kanata-112] explicitly name driver 6.2.0,
not the installed 6.8.0. The existing combination is an observed local setup,
not an upstream compatibility guarantee. [Current Kanata instructions][kanata]
describe a protocol change at 1.13.0 requiring driver 8.0.0. Do not independently
upgrade Kanata or install the newest driver on the assumption that they match.

The stable-path Kanata copy deliberately updates only when missing/broken or
when `~/.config/kanata/update-kanata` exists. Updating the Nix package alone does
not necessarily update that copy. Leave the update flag absent during this
preparation; investigate any pre-existing flag before applying a rebuild.

The [Karabiner changelog][karabiner] says upgrading from 15.9.0 or earlier to
16.2+ disables automatic service startup until the application is opened.
This repository uses only the virtual HID driver and deliberately disables
Karabiner's competing keyboard grabber. Do not blindly follow full Karabiner
remapping setup instructions: validate that the virtual HID daemon starts while
the competing Core Service remains stopped. There are unresolved [macOS 27
virtual-keyboard reports][driver-issue] even with Karabiner 16.3.0.

### Read-only checks before and after the eventual upgrade

```sh
sw_vers
/usr/local/bin/kanata-nix --version
pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice
systemextensionsctl list
pgrep -fl '^/usr/local/bin/kanata-nix.*--port 5829'
pgrep -x Karabiner-Core-Service
pgrep -x karabiner_grabber
hidutil list | grep -i karabiner
ls -l ~/.config/kanata/update-kanata
```

Expect one main Kanata process, no competing Core Service/grabber, an activated
and enabled driver extension, and `Karabiner DriverKit VirtualHIDKeyboard` in
`hidutil` output. The existing helper's older `ioreg -rn 'Karabiner VirtualHIDKeyboard'`
query returns empty output even with the current device present; it can also
exit successfully when nothing matches, so do not use that query or a helper's
healthy message as proof of a working device. The update flag should not exist.
Process/extension presence does
not prove that keystrokes work: manually test typing, home-row modifiers,
layout switching, sleep/wake, and login/unlock before accepting the upgrade.
Recheck Input Monitoring/Accessibility grants if input fails.

### Recovery — only when input is actually broken

Keep these instructions accessible from another device and save work first.
If remote recovery is needed, verify SSH access from that device beforehand;
do not assume the pending remote-access configuration is already deployed.

Try the existing root-owned recovery helper from a usable terminal or SSH:

```sh
sudo -n /run/current-system/sw/bin/kanata-ctl rescue
```

This interrupts input, neutralizes the competing grabber, resets the virtual HID
daemon and restarts Kanata. It cannot repair incompatible driver protocols or
grant macOS permissions automatically. Do not run it as a harmless health check.

Killing Kanata is not an emergency disable: launchd's `KeepAlive` restarts it.
To unload the remapper temporarily (requires ordinary administrator approval):

```sh
sudo launchctl bootout system/local.kanata
```

This is not a persistent disable across boot/activation, nor a guarantee that
native input recovers if the driver or another grabber is stuck. Restore the
installed job using its verified LaunchDaemon plist when safe. Do not reinstall
or remove the keyboard driver while keyboard access is your only recovery path.

## GUI apps fail to start after login or rebuild

Observed after upgrading mac-home to 27.2: `local.darwin-startup` exited with
`78: EX_CONFIG` before its script ran. The unified log reported `Unable to open
stdout path ... darwin-startup.log ... Permission denied`. Its two logs, and
the Vicinae keepalive logs, were root-owned mode 0644. This is a shared startup
failure, not evidence that Hammerspoon itself is incompatible with 27.2.

`darwin/common.nix` now prepares these four logs as the GUI user in
`preActivation`, before launchd services load. `darwin/scripts/prepare-gui-logs.sh`
preserves non-user-owned/unwritable logs in a private `.darwin-startup-logs.*`
directory beside them and creates private user-owned replacements. Writable
existing logs are not truncated; symlinks and non-regular files are rejected.
It never runs as root and does not recursively chown the user's Logs directory.

After log permissions are repaired, retry only the startup job:

```sh
launchctl kickstart -p gui/$(id -u)/local.darwin-startup
```

Successful one-shot jobs normally show `not running` afterward; check for last
exit code 0, a fresh `Startup script completed.` log entry, and running apps.
This recovery was verified on 27.2 without rebooting. A subsequent `sup` was
checked: both jobs exited successfully and all four logs stayed user-owned and
writable. Reboot behavior has not been retested.

## SketchyBar clicks reveal the native menu bar

Confirmed on mac-home after 27.2: the invisible `MenuBarAgent` window covered
the top 33 points at layer 25, above all SketchyBar item windows at layer 3.
This matches [SketchyBar #852][clicks] and is distinct from the window-stack
rendering fix in 2.24.1.

The initial `topmost=on` workaround restored clicks but covered the native menu.
It has been replaced by the exact [community patch][menu-patch] tested on this
Mac: strayer commit `dd43bf67dde4f5f9b31509d3ab85a37158d26777`, vendored as
`nixos/common/pkgs/sketchybar/macos27-menu-bar.patch`.

On macOS 27+, the patch raises a top bar to layer 26 while the native menu is
hidden, then restores the configured layer when the native menu appears. It
reacts to window-server notifications rather than polling or rebuilding windows.
`dotfiles/sketchybar/defaults.sh` again uses `topmost=window`, so the revealed
native menu can appear above SketchyBar. Older macOS versions and bottom bars
retain the configured layering. The wrapper refuses upstream versions other
than 2.24.1 until the patch is reviewed for an update or removed after an upstream fix.

The user confirmed the live test restored normal access to both bars on
mac-home/27.2. This remains an unofficial patch; multi-monitor, fullscreen, and
mac-work runtime behavior have not been certified. Tests evaluate both Mac
profiles, verify the exact patch bytes, execute the managed defaults and check
the version guard:

```sh
python3 -m unittest discover -s tests/sketchybar -v
```

Apply with `sup`, then restart the bar so the running executable matches the new
profile (a config reload alone does not replace a running binary):

```sh
sup
pkill -x sketchybar
/bin/zsh -lc 'sketchybar >/dev/null 2>&1 & disown'
```

## Remaining upgrade gates

- Make and verify a current Time Machine backup; Nix generations cannot roll
  back macOS. Save work and shut down VMs/containers before the OS installer.
- After changing the SketchyBar package, test empty-bar clicks, popups, NanoWM
  tags, fullscreen transitions, and external-display reconnects on the target Mac.
- Apple lists [external-display settings/arrangement restoration][apple] as a
  27.2 known issue. Record the current layout and check it after reconnecting;
  do not assume NanoWM's monitor/tag assignment will remain unchanged.
- JankyBorders 1.9.0 has [Mission Control artifacts][borders]. Temporarily disable
  borders with the existing NanoWM toggle if needed; no unreviewed fork is installed.
- NanoWM does not call the [broken Hammerspoon Spaces APIs][spaces], but still
  needs manual tiling, focus, native-fullscreen and multi-monitor validation.
- Smoke-test Colima/Testcontainers, UTM, the Linux builder, local-model Metal
  inference, and `no-sleep` behavior after upgrade. They have not been certified
  here on macOS 27.2. No automatic reboot, sleep/lid test or driver reset is part
  of preparation.

[sketchybar]: https://github.com/FelixKratz/SketchyBar/issues/850
[kanata-112]: https://github.com/jtroo/kanata/blob/v1.12.0/docs/release-template.md
[kanata]: https://github.com/jtroo/kanata/blob/main/docs/setup-macos.md
[karabiner]: https://karabiner-elements.pqrs.org/docs/releasenotes/
[driver-issue]: https://github.com/pqrs-org/Karabiner-Elements/issues/4587
[apple]: https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes
[borders]: https://github.com/FelixKratz/JankyBorders/issues/209
[spaces]: https://github.com/Hammerspoon/hammerspoon/issues/3897
[clicks]: https://github.com/FelixKratz/SketchyBar/issues/852
[menu-patch]: https://github.com/strayer/SketchyBar/commit/dd43bf67dde4f5f9b31509d3ab85a37158d26777
