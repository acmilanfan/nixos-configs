{ pkgs, lib, ... }: {

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
  # per-session spice-vdagent client is what actually receives the host's
  # resolution-change requests and applies them — without it, resizing the UTM
  # window does nothing. Run it for this user session.
  systemd.user.services.spice-vdagent = {
    Unit = {
      Description = "SPICE vdagent (session client)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.spice-vdagent}/bin/spice-vdagent";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
