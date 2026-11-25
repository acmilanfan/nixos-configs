# Linux desktop review: open issues

Review of 2026-11-25, done from a Mac: every item below comes from reading the
code and evaluating the config, none was reproduced on a Linux machine. Anchors
were rechecked against the code on the same day. Already fixed from the same
review: vm-hyprland evaluation (`f9a34e6`), howdy as `required` on every PAM
service (`6c4021e`), hyprlock inheriting the start lock (`ad2c380`).

Most severe first. Each item: where, what goes wrong, a fix to start from.
`scripts/…` means `nixos/home-manager/common/scripts/…`; `hyprland.nix` is
`nixos/home-manager/common/hyprland.nix`.

## Services and session

### 1. Fallback Waybar dies with the quickshell unit

- **Where:** `nixos/yogabook-gen10/home-manager/custom.nix` (`quickshell-shell`,
  `ExecStopPost = hypr-waybar-toggle on`); `nixos/home-manager/common/scripts/hypr-waybar-toggle`.
- **What:** after `ExecStopPost` finishes, systemd kills everything left in the
  unit's cgroup (`KillMode=control-group`). The Waybars `hypr-waybar-toggle on`
  starts with `nohup … &` are in that cgroup, so stopping or crashing the shell
  leaves no bar at all.
- **Also:** `hypr-waybar-toggle on` itself runs `pkill` on quickshell, which
  fires the same `ExecStopPost` concurrently, and its `kill_waybar` can kill the
  bars the user just started.
- **Fix:** start the bars outside the unit (`systemd-run --user --scope`, or
  `hyprctl dispatch exec`), or make Waybar its own unit with `Conflicts=` on
  `quickshell-shell`.

### 2. Bottom Waybar started by yb-mode has the daemon's PATH

- **Where:** `nixos/yogabook-gen10/home-manager/yb-touchpad.nix` (`ybModePath`,
  `Environment = PATH=…`); `scripts/yb-mode` (`show_bottom_bar`).
- **What:** the service PATH holds only bash, coreutils, hyprland, jq, procps,
  swaybg, systemd, waybar, wvkbd and yb-touchpad. The Waybar it spawns inherits
  it, so its custom modules and click actions fail with "command not found"
  (`hypr-kanata-status`, `hypr-layout-status`, `hypr-power-watts`, `hypr-timer`,
  `hypr-ai-agents`, `hypr-idle-inhibit`, `hypr-touch-menu`, `wlogout`,
  `pavucontrol`) whenever quickshell isn't running.
- **Also:** that Waybar, swaybg, wvkbd and the pad window all live in yb-mode's
  cgroup, so a restart of yb-mode (e.g. a Home Manager switch) kills them.
- **Fix:** append `/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin`
  to the PATH, and spawn long-lived children via `systemd-run --user` or
  `hyprctl dispatch exec`.

### 3. hyprlock-absence / hyprlock-proximity unit definitions

- **Where:** `nixos/home-manager/common/hyprland.nix` (`hyprlock-proximity`,
  `hyprlock-absence`); `scripts/hyprlock-absence` (the "No proximity sensors
  found" `exit 0`).
- **What:**
  - Without the sensors (t480-home, vm-hyprland) hyprlock-absence exits 0, but
    `Restart=always` with no `RestartSec` restarts it until the start limit,
    so it sits in `failed` every login. hyprlock-proximity has no such check
    and polls `hyprctl` every 0.5 s forever on those hosts.
  - Neither has `PartOf=graphical-session.target`. After logout and login they
    keep running with the old `HYPRLAND_INSTANCE_SIGNATURE`, `hyprctl locked`
    never returns true, and presence wake and absence lock silently stop.
- **Fix:** add `PartOf`, use `ConditionPathExists=` on the sensor paths (or
  `Restart=on-failure`), and exit early in proximity too.

### 4. Auto-rotation stops for good when monitor-sensor exits

- **Where:** `scripts/hypr-iio-rotate` (`monitor-sensor | while …`);
  `hyprland.nix` (`hypr-iio-rotate`, `Restart = "on-failure"`).
- **What:** if `monitor-sensor` exits (e.g. iio-sensor-proxy restarts), the
  pipeline returns the loop's status, 0, so `on-failure` never restarts it.
- **Fix:** `Restart=always` with `RestartSec=2`, or `exit 1` after the loop.

### 5. No wallpaper is ever set

- **Where:** `dotfiles/hypr/hyprland.lua` (`swww init`, `swww img …`);
  `hyprland.nix` installs `awww`.
- **What:** `awww` ships only `awww`/`awww-daemon` (`swww` is just a nixpkgs
  alias), and `init` was removed upstream.
- **Fix:** start `awww-daemon` and use `awww img …`.

### 6. yb-mode applies each mode twice, concurrently

- **Where:** `scripts/yb-mode` (`set_mode`, and the daemon loop comparing
  `previous_mode`).
- **What:** `set_mode` (SUPER+M) applies the mode itself; within 0.5 s the
  daemon sees the new mode and applies it again, possibly while the first is
  still running. wvkbd and the pad are torn down and restarted twice, and the
  two `start_wvkbd` runs race on `wvkbd.pid` and on focus.
- **Fix:** have `set_mode` only write the override and let the daemon apply
  it, or serialise applies with a lock.

## yb-touchpad (`apps/yb-touchpad`)

### 7. Long-press drag can pick a window on another workspace (code confirmed)

- **Where:** `src/ipc.rs` (`parse_clients`), `src/watch.rs` (`pick_target`).
- **What:** `parse_clients` drops `workspace`/`hidden`, and `pick_target`
  takes the last client whose rectangle contains the point, across all
  workspaces. In laptop mode all workspaces sit on eDP-1, so this is common:
  the drag then resizes or floats the active window based on another window.
- **Fix:** filter by the monitor's `activeWorkspace.id` and `!hidden`, or use
  `hyprctl activewindow -j`.

### 8. Rotation and the top panel's calibration are ignored (code confirmed, effect on the device not)

- **Where:** `src/coord.rs` (`device_to_screen`), `src/ipc.rs` (monitor size),
  `src/watch.rs` (raw evdev reads); `nixos/yogabook-gen10/configs/env.nix`
  (`LIBINPUT_CALIBRATION_MATRIX="-1 0 1 0 -1 1 0 0 1"` on the top touchscreen).
- **What:** raw coordinates map linearly onto the unrotated monitor size, but
  hypr-iio-rotate applies transforms 1–3 to both panels, so taps, edge swipes
  and pad hit-tests land in the wrong place when rotated. The daemon also never
  applies the top panel's 180° calibration, so top-screen gestures may come out
  mirrored.
- **Fix:** read the monitor `transform` and apply rotation and inversion
  before `device_to_screen`.

### 9. A re-plugged touchscreen can be missed for good

- **Where:** `src/watch.rs` (device scan and inotify setup), `src/devscan.rs`.
- **What:** the inotify watch is added after the scan, so a node that appears
  in between is never seen; and on CREATE the node is still root-only until
  udev's chmod (an ATTRIB event), so `open` fails with EACCES and the error is
  swallowed. After a USB re-enumeration (e.g. resume) gestures stay dead while
  the unit looks healthy.
- **Fix:** watch before scanning, add ATTRIB to the mask, rescan periodically.

## Smaller

- **Suspend during remote sessions:** hypridle's 1800 s `systemctl suspend`
  ignores SSH activity, so yogabook/t480 suspend in the middle of a Tailscale
  SSH session. Hold a `systemd-inhibit` while sshd sessions exist, and mention
  it in `docs/remote-access.md`.
- **Yoga Book commands on every host:** `hyprland.nix` hypridle calls
  `set-sync-brightness` / `restore-sync-brightness`, which exist only on
  yogabook-gen10; they fail quietly on t480 and vm-hyprland.
- **Hardcoded UID:** `dotfiles/hypr/hyprland.lua` links
  `/run/user/1000/ssh-agent`; use `$XDG_RUNTIME_DIR`.
- **Stale comment:** `nixos/vm-hyprland/configs/ssh.nix` says no real host runs
  sshd, no longer true with remote access.
- **CI runner and docker:** the `weekenduo-ci` shell-executor user is in the
  `docker` group (`nixos/common/ci-runner/default.nix`), so any CI job is
  effectively root on yogabook. Fine only while no untrusted MR/fork pipelines
  run there.
- **hidraw access:** `nixos/common/services.nix` gives every hidraw device
  mode 0660 group `users` (raw keyboard and FIDO access); the Vial-specific rule
  on the line above already covers the stated need.

## shellcheck warnings in Linux-only scripts

`shellcheck -S warning`, all low risk:

- unused variables (SC2034): `dotfiles/kanata/reload-kanata-linux.sh` (`i`),
  `dotfiles/kanata/switch-kanata-linux.sh` (`SCRIPT_DIR`),
  `dotfiles/waybar/scripts/kanata-status.sh` (`in_kbd`),
  `nixos/common/scripts/display-arrange` (`b_main`),
  `scripts/hypr-ai-agents` (`project`, `cwd`, `title`),
  `scripts/hypr-quickshell-shell` (`waybar_pattern`),
  `scripts/hyprlock-session` (`i`), `scripts/touch-toggle` (`TOUCH_DEVICE`),
  `scripts/yb-mode` (`i`);
- `local x=$(…)` masking the exit status (SC2155): `scripts/hypr-profile`
  (6 places), `scripts/yb-mode` (1);
- word-split array from command output (SC2207): `scripts/hypr-focus-other-monitor`;
- `scripts/kb-taps` is not a POSIX/bash script, so shellcheck skips it.
