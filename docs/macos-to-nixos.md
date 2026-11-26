# Reproducing the Mac setup on NixOS

Assessment from 2026-11-11 of what it would take to run the `mac-home` / `mac-work` setup on
NixOS, what changes, and what cannot be carried over.

The Mac setup is largely a Linux tiling desktop re-created on macOS: NanoWM mimics Hyprland's
tags, SketchyBar plays waybar's role, and Vicinae, kanata and warpd are Linux-first tools.
`t480-home` and `yogabook-gen10` already run the Linux originals, so the reverse direction is
mostly a parity exercise. The real limits are hardware, the Apple ecosystem and employer policy.

## Hard blockers

| Blocker | Why |
|---|---|
| NixOS on these Macs | `mac-work` is an M3 Pro, `mac-home` (14 cores / 48 GB) an M4 Pro class chip. Asahi Linux supported only M1/M2 at the time of writing (check asahilinux.org). On these machines NixOS means a VM (`vm-hyprland`) or other hardware. |
| `mac-work` is employer-managed | It is MDM-enrolled and runs mandatory endpoint-security and VPN clients. Linux versions of such tools often exist, but NixOS is rarely a supported target and MDM does not cover it. A NixOS work machine is an IT approval question, not a config one. |
| oMLX / MLX | Apple Silicon only. The value of `mac-home` for local models is 48 GB of unified memory (`iogpu.wired_limit_mb`). On Linux this needs llama.cpp or vLLM on a GPU with comparable VRAM; the ThinkPad/Yoga Book would run Ollama CPU-only. |
| macOS VMs | UTM runs macOS guests on a Mac; macOS on non-Apple hardware breaks the licence and is fragile. |

## Applications (Brewfile in `darwin/common.nix`)

- **Native on Linux, same or better:** Chrome, Firefox, Slack, Nextcloud, firefoxpwa, wifitui
  (`iwmenu` already used), Docker (native, no colima VM, simpler Testcontainers), Vicinae.
- **Built into Hyprland / libinput / PipeWire:** AutoRaise (`follow_mouse`), Scroll Reverser
  (per-device natural scroll), MiddleClick (clickfinger), Cursorcerer
  (`cursor:inactive_timeout`), displayplacer (`hypr-profile`), FineTune (PipeWire per-app volume
  and routing), macpow (`hypr-power-watts`).
- **Replaced by another tool:** Raycast → Vicinae (runs Raycast extensions); UTM →
  libvirt/virt-manager or quickemu; balenaEtcher → `dd` or Impression; CleanupBuddy →
  `kanata-disabled.kbd`; mole → `nix-collect-garbage` plus `ncdu`.
- **No Linux app:** ChatGPT desktop (use a PWA).

## Own macOS tooling

**Dropped entirely.** Much of `darwin/common.nix` works around macOS itself and has no Linux
counterpart: keeping TCC grants alive (stable binary paths, the self-signed kanata identity,
quarantine stripping), the Karabiner VirtualHIDDevice driver and neutralised grabber, launchd and
Gatekeeper workarounds, and the linux-builder VM (builds are native). kanata writes to `uinput`
directly.

**Ported, roughly by effort:**

| Mac piece | Linux route |
|---|---|
| NanoWM (Accessibility-API window management) | Hyprland natively: master layout, special workspace, hyprexpo, two tag banks are already in `dotfiles/hypr/hyprland.lua`. |
| SketchyBar plugins (agents, kanata, timer, no-sleep) | waybar modules; `hypr-ai-agents` and `hypr-timer` exist. |
| `no-sleep` closed-lid mode | logind `HandleLidSwitch` (`nixos/common/xserver.nix`) or `systemd-inhibit --what=handle-lid-switch`. |
| `zoom-hold.lua` | `cursor:zoom_factor`, already bound in `hyprland.lua`. |
| `nanowm/yazi-picker.lua` | Better on Linux: `xdg-desktop-portal-termfilechooser` makes yazi the real file picker for portal-using apps. |
| `nanowm/pass.lua` | `vicinae dmenu` with a small script, or tessen. |
| `sweep-remapper.lua`, `firefox-tab-mode.lua` (per-app key remaps) | Harder: kanata sits below the compositor and cannot see the focused app. Listen on Hyprland's event socket and switch kanata layers over its TCP port, or use keyd's application mapper. |
| Menu walker in `nanowm/menus.lua` (palette over any app's menus) | Not possible in general: Wayland has no global menu bar; only some Qt/KDE apps export menus over D-Bus. |

## Inter-app integration

macOS offers one system-wide set of hooks (Accessibility API, event taps, Apple Events, URL
schemes, Spotlight, Keychain, Continuity). Linux splits them, and Wayland blocks some on purpose.

| macOS hook | Linux equivalent | Verdict |
|---|---|---|
| Accessibility API: move/inspect other apps' windows | Only the compositor can; Hyprland IPC does it more reliably and without permission prompts | Window management better |
| Accessibility API: read UI trees, type into apps | AT-SPI (GTK/Firefox decent, Electron needs a flag), `wtype`/`ydotool` | Partial |
| Global menu bar | Nothing universal | Lost |
| Global key interception | kanata/keyd (app-blind) plus Hyprland binds (app-aware) | Fine combined |
| URL schemes (`hammerspoon://…`) | `x-scheme-handler` in a `.desktop` file, or `hyprctl` / a unix socket | Fine |
| Apple Events / AppleScript / Shortcuts | D-Bus; MPRIS + `playerctl` is more standard than `nowplaying-cli`; app scripting mostly limited to KDE apps | Mixed |
| Spotlight index | localsearch/baloo, `fd`/`plocate`; Vicinae has its own file index | Weaker |
| Keychain | Secret Service (gnome-keyring), used by Chrome, Slack, git; `pass` already in use | Fine, no iPhone-synced passkeys |
| Native open/save dialogs | xdg-desktop-portal | Better (yazi as picker) |
| Screen sharing | PipeWire portal: fine in browsers and Slack, weaker in native Zoom | Mostly fine |
| Continuity (Universal Clipboard, AirDrop, Handoff, iPhone Mirroring, SMS relay, Watch unlock, AirPods switching, iCloud Photos) | KDE Connect (full with Android, limited with iPhone), LocalSend, Nextcloud | Mostly lost with an iPhone |
| Hardware feel (battery, instant wake, trackpad) | ThinkPad-class hardware | Noticeably worse |

## Conclusion

- **`mac-home` → NixOS on other hardware:** about 90% is already in this repo. Lost: MLX and large
  local models (without a big GPU), Continuity with Apple devices, the menu palette, battery life.
- **`mac-work` → NixOS:** the same technically, but blocked on employer device policy.
- **On the current Macs:** keep macOS and use `vm-hyprland` (`docs/vm-hyprland.md`) as the NixOS
  environment.
