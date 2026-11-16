# Reproducing the work/home Mac setup on NixOS

Assessment: 2026-11-11. Saved: 2026-11-16.

**Most of the working environment can be reproduced on NixOS. Reproducing the
complete macOS experience, especially its cross-app integration, is a different
matter.**

The difficult part is not Neovim, terminals, browsers, or development tools. It
is the automation connecting them.

This assessment covers the repository's work/home Mac configurations,
Hammerspoon/NanoWM, Vicinae, and existing Linux configuration. It is a
configuration/documentation audit, not an end-to-end Linux test. Package
availability does not establish feature parity or runtime compatibility.
Hardware support and product capabilities below are time-sensitive; recheck the
linked upstream documentation before making a migration decision.

## Hardware: another laptop versus the existing Macs

- **YogaBook/T480 or another Linux-compatible PC:** a realistic migration.
- **Existing NixOS VM:** useful for testing workflows, but not battery life,
  suspend, trackpad feel, or physical-device compatibility.
- **Replacing macOS on mac-home:** not a practical daily-driver option at the
  time of this assessment.

The machine inspected was an **M4 Pro MacBook Pro with 48 GB RAM**. Asahi's
[M4 support matrix](https://asahilinux.org/docs/platform/feature-support/m4/)
listed no installer for M4 Pro/Max, with GPU, sleep, Wi-Fi, and many other
essential features unavailable. NixOS cannot configure around missing hardware
support. The work Mac's hardware was not inspected directly.

The rest of this assessment assumes **NixOS on supported hardware**.

## What carries over

| Current workflow | NixOS assessment |
| --- | --- |
| Neovim, orgmode, Git, zsh, direnv, tmux | Strong portability. Much is already shared through Home Manager. |
| Ghostty, Alacritty, Firefox, Chrome, Slack, Telegram | Linux versions exist, but desktop behavior and individual features can differ. The ARM VM is not representative of x86 Linux app availability. |
| Hosted AI tools and MCP services | Largely portable. Credentials, service startup, notifications, and terminal focusing need platform-specific plumbing. |
| NanoWM tiling, tags, scratchpads, focus, floating rules | Most concepts map well to Hyprland. The Linux config already implements many of them. Exact layout behavior and shortcuts are not identical. |
| SketchyBar | Replace with Waybar or another Linux shell/bar. The information and actions are reproducible; the implementation is not portable. |
| Kanata | Feasible, and already configured on the YogaBook. Device selection, permissions, modifier mappings, and app-specific behavior differ. |
| Vicinae | A good bridge between platforms, but the Linux deployment currently has substantially fewer extensions. |
| Syncthing and Nextcloud | Both already have Linux configuration. Existing data, identities, and credentials still need migration. |
| Colima/Docker/Testcontainers | Usually simpler on Linux: containers run without the extra macOS Linux VM. Colima-specific environment overrides must not follow unchanged. |
| Yazi and orgmode launchers | Portable tools; focus-or-create behavior needs Linux integration. Several orgmode launchers already exist. |
| OCR using Apple Vision | Requires another OCR engine and clipboard/screenshot plumbing. Similar workflow, potentially different recognition quality. |
| Local AI using oMLX/Metal | Not portable unchanged. Linux inference depends on different GPU backends and memory constraints. Keeping the Mac as an inference server is another option. |

The terminal-centred environment is much closer to portable than the desktop
automation layer.

## Can Linux apps integrate like macOS apps?

**Yes. Linux has substantial cross-app integration. What it lacks is one
uniformly implemented desktop contract across all applications.**

macOS provides relatively consistent building blocks:

- Standard application menus and command routing.
- Accessibility APIs for inspecting controls and manipulating text.
- LaunchServices for opening documents, URLs, and applications.
- Typed clipboard and drag-and-drop data.
- Common file dialogs, previews, text services, and credential APIs.
- Apple Events/AppleScript in applications that support scripting.

Not every Mac app follows all these conventions. Nevertheless, the Hammerspoon
setup benefits heavily from them.

Linux has corresponding building blocks:

| Integration | Linux mechanism |
| --- | --- |
| Open files and URLs in another app | Desktop entries, MIME associations, URL handlers |
| Communicate with running apps | D-Bus, application-specific APIs, sockets and CLIs |
| Inspect accessible UI controls | AT-SPI |
| File picking, screen sharing, certain global shortcuts | XDG desktop portals |
| Audio routing and screen-sharing streams | PipeWire and related services |
| Shared credential storage | Secret Service implementations and desktop wallets |
| Window/workspace automation | Compositor-specific APIs |

The important difference is **coverage**. GTK, Qt, Electron, Java, and
custom-rendered apps may expose different amounts of functionality.

A Linux desktop can be tightly integrated. But with Hyprland, more of that
integration must be assembled explicitly.

### App-menu palette

The `Alt+M` Hammerspoon palette reads the foreground app's menu tree and executes
the selected command:

[`dotfiles/hammerspoon/nanowm/menus.lua`](../dotfiles/hammerspoon/nanowm/menus.lua)

On Linux, some applications expose menus through accessibility or exported-menu
interfaces. Others use hamburger menus, custom widgets, or their own command
palettes.

**Do not assume one Linux replacement will expose every application's commands
consistently.** This is a bigger potential loss than replacing SketchyBar.

### Shortcat, VimMode, and keyboard-driven UI control

These are three different capabilities:

1. Moving the pointer using the keyboard.
2. Sending navigation/editing keystrokes.
3. Understanding UI elements and activating them by name or hint.

Linux can do all three in some circumstances, but a pointer grid is not a
complete Shortcat replacement, and an arrow-key remapper is not equivalent to
accessibility-aware text editing.

The current Linux Vim submap is much simpler than the Mac setup.

Wayland intentionally restricts arbitrary input interception and injection.
Approved portals, compositor interfaces, or lower-level input access can provide
functionality, but there is no universally interchangeable Hammerspoon API.

That does not mean Wayland prevents accessibility altogether; UI accessibility
and input injection are separate mechanisms.

### Yazi file-dialog integration

The Mac bridge finds a native Open dialog, launches Yazi, then fills the dialog's
path field through Accessibility:

[`dotfiles/hammerspoon/nanowm/yazi-picker.lua`](../dotfiles/hammerspoon/nanowm/yazi-picker.lua)

Linux offers a different approach: make Yazi the file chooser through a
[terminal file-chooser portal](https://github.com/hunkyburrito/xdg-desktop-portal-termfilechooser).

For applications using that portal:

```text
Upload/Open → Yazi → selected file returned to application
```

That avoids some focus and keystroke automation and could make the integration
cleaner than the Mac bridge.

**Limitation:** applications with their own dialogs or without portal
integration will not automatically participate.

### Clipboard and drag-and-drop

Ordinary text, screenshots, files, and URLs can move between Linux apps.

The less uniform cases include:

- Rich text versus plain text.
- Copying a file versus its pathname.
- Dragging attachments between different application toolkits.
- Clipboard persistence after the source app closes.
- Preventing password managers' clipboard contents entering history.

The Mac password chooser explicitly marks copied passwords with a concealed
clipboard type. **That safety property needs a deliberate Linux equivalent**,
not just replacing `pbcopy` with `wl-copy`.

### Screen sharing

Linux supports screen and window sharing through portals and PipeWire.
Hyprland's
[portal documentation](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/)
describes screen sharing and global shortcuts.

However, the exact browser/calling-app combination matters, especially for:

- Individual-window sharing.
- System-audio sharing.
- Remote control.
- Older XWayland applications.
- Sharing after suspend or monitor changes.

For work, test the real meeting workflow, not merely whether the calling app
launches.

## What cannot be reproduced directly

### Mac-only software and Apple frameworks

Hammerspoon, the existing NanoWM implementation, SketchyBar, Shortcat, and
AppleScript integrations do not simply become Linux applications.

Their outcomes may be replaceable. Their code and APIs generally are not.

Likewise, macOS `.app` bundles do not run natively on Linux. Wine is primarily a
Windows compatibility layer, not a macOS compatibility solution.

### Apple ecosystem features

If used, there is no supported, complete Linux replacement for the whole
combination of:

- Handoff and Universal Clipboard.
- Sidecar and Universal Control.
- Apple Watch unlock.
- iCloud Keychain and Apple-specific authentication integration.
- AirDrop and Continuity features.

There are partial alternatives, especially with Android, but not equivalent
membership in Apple's ecosystem.

The current config explicitly disables AirDrop, so it should not automatically
be counted as an actual loss for this setup.

### Platform-specific integrations inside portable products

An application existing on Linux does not imply every integration exists there.

For example, ChatGPT's documented
[macOS Work with Apps](https://help.openai.com/en/articles/10119604-work-with-apps-on-macos)
uses macOS Accessibility and editor extensions. That particular integration
cannot be assumed to transfer with the chat interface. This is an example of
platform-dependent behavior, not confirmation that the feature is used here.

### Apple development and hardware-specific facilities

If needed, Xcode, Apple's simulators, and supported local Apple-platform
build/signing workflows still require macOS.

Similarly, Mac Touch ID and the existing Metal-based inference setup are not
capabilities NixOS can reproduce merely through configuration.

## Everyday differences

- **Keyboard conventions:** macOS separates Command shortcuts from terminal
  Control shortcuts. Linux typically uses Control for application shortcuts.
  Much of the muscle memory can be preserved, but a blanket remap creates
  conflicts.
- **Application lifecycle:** close window, quit app, activate app, and create
  new window are less uniform across Linux apps. Focus-or-create launchers must
  account for this.
- **File management:** previews, PDF annotation, network mounts, and reveal in
  file manager are available, but distributed across different applications
  rather than Finder/Preview conventions.
- **Displays and input:** scaling, gestures, trackpad feel, docking, and suspend
  depend on the hardware, compositor, and application mix. Neither identical
  behavior nor worse behavior is guaranteed.
- **Maintenance:** Mac-specific TCC, signing, and Karabiner-driver workarounds
  disappear, but responsibility shifts to portals, session services, desktop
  components, and their compatibility.
- **NixOS-specific friction:** downloaded Linux binaries and vendor installers
  may expect conventional filesystem paths. Some need packaging, patching, or
  an FHS/container environment.
- **Work-device policy:** VPN, endpoint protection, device compliance,
  certificates, and SSO could block migration even if all coding tools work.
  The repo cannot establish employer support.

## Existing Linux configuration gaps

These were concrete source-level differences at the time of assessment, not
inherent Linux limitations:

- **Vicinae:** Linux explicitly deploys only the Nix and Hyprland-keybind
  extensions; the Mac branch deploys many more. See
  [`vicinae.nix`](../nixos/home-manager/common/vicinae.nix).
- **Agent bar:**
  [`hypr-ai-agents`](../nixos/home-manager/common/scripts/hypr-ai-agents) counts
  Claude/Gemini/Antigravity, but not OpenCode. Its focusing path also does not
  use the newer shared title-based helper.
- **Warpd:** the Linux configuration starts it daemon-style, while upstream
  documents [Wayland-specific limitations](https://github.com/rvaiya/warpd#wayland),
  including no daemon mode. That integration needs revisiting.
- **Window behavior:** Linux uses Alacritty as its default launcher, and the
  shortcuts/layout semantics differ from NanoWM.
- **Gestures/overview:** parts of the Hyprland gesture and overview
  configuration are commented out.
- **VM limitations:** the VM intentionally omits secrets and has documented
  scaling differences. It is not currently a complete work-environment
  reproduction. See [vm-hyprland.md](vm-hyprland.md).

Relevant desktop source:
[`dotfiles/hypr/hyprland.lua`](../dotfiles/hypr/hyprland.lua) and
[`nixos/home-manager/common/hyprland.nix`](../nixos/home-manager/common/hyprland.nix).

## Recommended direction

| Direction | Best fit |
| --- | --- |
| NixOS + Hyprland | Preserve the keyboard-driven, tiled, programmable workflow. Most reuse of the existing Linux configuration. |
| NixOS + KDE Plasma | Prioritise a cohesive desktop: file manager, settings, notifications, wallet, display management, and desktop integration. Less like NanoWM by default. |
| macOS desktop + Linux VM/remote machine | Keep Mac-native integration while moving development/runtime work to Linux. Lowest migration risk. |

**Trial Hyprland on the YogaBook before considering a full switch.** Judge it
using actual tasks:

- Upload through Yazi.
- Navigate an app without the mouse.
- Invoke an app-menu command.
- Share a window with audio in the actual work meeting application.
- Focus the correct AI session.
- Dock and undock.
- Resume from sleep.

**Bottom line:** Linux can reproduce, and sometimes improve, the programmable
development workflow. It cannot promise the same uniform cross-app behaviour
as macOS. The deciding factors are likely Shortcat/VimMode, the app-menu palette,
meeting integration, and hardware quality—not package availability.
