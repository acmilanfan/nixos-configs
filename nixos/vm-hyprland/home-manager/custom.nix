{ config, pkgs, lib, ... }:
let
  # UTM's Auto Resolution sends the window size (in Retina pixels) to the
  # SPICE agent as a "monitors config" message; it never changes virtio-gpu's
  # preferred mode, which stays at QEMU's 1280x800. spice-vdagent only knows
  # how to apply that via XRandR, which fails under XWayland, so read the
  # requested size from its debug output and apply it to Hyprland ourselves.
  # scale=2 because UTM's "native resolution" hands the guest Retina pixels.
  spice-vdagent-hyprland = pkgs.writeShellApplication {
    name = "spice-vdagent-hyprland";
    runtimeInputs = [ config.wayland.windowManager.hyprland.finalPackage pkgs.jq pkgs.spice-vdagent ];
    text = ''
      apply() {
        local mode=$1 cur
        cur=$(hyprctl monitors -j | jq -r '.[] | select(.name == "Virtual-1") | "\(.width)x\(.height)"') || return 0
        [[ "$cur" == "$mode" ]] && return 0
        echo "Virtual-1: $cur -> $mode"
        hyprctl eval "hl.monitor({output='Virtual-1',mode='$mode',position='0x0',scale=2})" || true
      }

      # -x: stay in the foreground, or systemd sees the main process exit and
      # stops the unit (taking the forked agent with it). -d: log the
      # "monitor 0, config WxH+X+Y" lines this reads; the stderr copy is
      # prefixed with "spice-vdagent[PID]: ", so the match isn't anchored.
      spice-vdagent -x -d 2>&1 | while IFS= read -r line; do
        [[ "$line" =~ monitor\ 0,\ config\ ([0-9]+x[0-9]+)\+ ]] || continue
        mode=''${BASH_REMATCH[1]}
        # A window drag sends a burst; apply only the last size of it. At
        # session start UTM's burst also carries QEMU's boot size 1280x800
        # after the real window size; skip that unless it's all there is.
        while IFS= read -r -t 0.3 line; do
          [[ "$line" =~ monitor\ 0,\ config\ ([0-9]+x[0-9]+)\+ ]] || continue
          [[ "''${BASH_REMATCH[1]}" == 1280x800 && "$mode" != 1280x800 ]] && continue
          mode=''${BASH_REMATCH[1]}
        done
        apply "$mode"
      done
    '';
  };
in {

  # While the SPICE agent is attached, UTM's pointer goes through
  # spice-vdagentd's uinput tablet, whose range is the guest resolution the
  # agent reports: XWayland's root window size. At scale 2 that's half the
  # pixel size UTM's coordinates use, so the cursor was mis-mapped until input
  # was captured (relative USB mouse). force_zero_scaling makes XWayland's root
  # the pixel size. X11 apps render unscaled (small) as a result.
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    hl.config({ xwayland = { force_zero_scaling = true } })
  '';

  programs.rofi = { extraConfig = { dpi = 0; }; };

  home.pointerCursor = { size = lib.mkForce 48; };

  # Alacritty renders an opaque black window under this VM's GL stack
  # (virtio-gpu-gl-pci -> virgl -> ANGLE -> Apple Metal): the hardware-GL path
  # fails while GTK apps work because they fall back to software rendering.
  # Force llvmpipe for alacritty only (verified to render correctly); a
  # terminal needs no GPU acceleration.
  programs.alacritty.package = pkgs.writeShellScriptBin "alacritty" ''
    export LIBGL_ALWAYS_SOFTWARE=1
    exec ${pkgs.alacritty}/bin/alacritty "$@"
  '';

  # The real hosts run one waybar per physical monitor (eDP-1/eDP-2/DP-*), but
  # this VM has a single virtio display named "Virtual-1" — the shared
  # config-hypr-top pins `output` to eDP-1 so nothing maps. Point the top bar
  # at Virtual-1 instead; config-hypr-bottom/external target nonexistent
  # monitors and are no-ops here, and the shared hypr-waybar-toggle script
  # still starts all three configs unchanged.
  home.file.".config/waybar/config-hypr-top".source = lib.mkForce ./waybar-virtual1.json;

  # spice-vdagentd (the system daemon) is enabled in the NixOS config, but the
  # per-session spice-vdagent client is what receives the host's
  # resolution-change requests; see spice-vdagent-hyprland above.
  systemd.user.services.spice-vdagent = {
    Unit = {
      Description = "SPICE vdagent (session client), applying UTM's window size to Hyprland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe spice-vdagent-hyprland;
      Restart = "always";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # secrets/secrets.yaml is encrypted only to the admin GPG key, which this
  # VM doesn't have, so sops-nix fails and aborts Home Manager activation.
  customSops.enable = false;

}
