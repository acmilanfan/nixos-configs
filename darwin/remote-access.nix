{ config, lib, ... }:
{
  # Native launchd daemon: no GUI login/app required. Enroll locally once with
  # sudo tailscale up --ssh=false; don't run a second Tailscale app alongside it.
  services.tailscale.enable = true;
  # Daemon-level gate also blocks persisted RunSSH=true preferences at startup
  # and rejects later attempts to enable Tailscale's separate SSH server.
  launchd.daemons.tailscaled.serviceConfig.EnvironmentVariables.TS_DISABLE_SSH_SERVER = "true";

  # Replace (do not append to) common.nix's AllowUsers: multiple AllowUsers
  # entries accumulate and its bare username would allow non-tailnet sources.
  # Keep the existing common hardening. mac-work does not import this module.
  services.openssh.extraConfig = lib.mkForce ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthenticationMethods publickey
    PermitRootLogin no
    AllowUsers ${config.system.primaryUser}@100.64.0.0/10 ${config.system.primaryUser}@fd7a:115c:a1e0::/48
    MaxAuthTries 3
    LoginGraceTime 30
    X11Forwarding no
  '';
}
