{ config, username, ... }:
{
  # Opt-in terminal access for the two personal laptops, not the VM.
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP transport only, not public SSH.
    # Let the NixOS firewall control tunnel ingress too. Tailscale's default
    # netfilter rules otherwise accept all traffic arriving on tailscale0.
    extraSetFlags = [
      "--netfilter-mode=off"
      "--ssh=false"
    ];
  };
  # Unlike clearing a preference after startup, this gate prevents a persisted
  # Tailscale SSH server from intercepting TCP/22 even before tailscaled-set runs.
  systemd.services.tailscaled.environment.TS_DISABLE_SSH_SERVER = "true";

  networking.firewall = {
    interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [ 22 ];
    checkReversePath = "loose";
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
      PermitRootLogin = "no";
      AllowUsers = [
        "${username}@100.64.0.0/10"
        "${username}@fd7a:115c:a1e0::/48"
      ];
    };
  };
}
