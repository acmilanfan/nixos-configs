{ pkgs, ... }:
let
  remote = hostname: {
    HostName = hostname;
    User = "gentooway";
    IdentityFile = "~/.ssh/id_ed25519_remote";
    IdentitiesOnly = true;
    ForwardAgent = false;
    PasswordAuthentication = false;
    StrictHostKeyChecking = "ask";
    ServerAliveInterval = 30;
    ServerAliveCountMax = 3;
    ConnectTimeout = 10;
    # Require a registered peer before dialing: `nc <short-name>` alone can
    # fall back to ordinary DNS. The daemon supplies the actual tailnet IP,
    # independent of macOS search domains. SSH still verifies the host key.
    ProxyCommand = "${pkgs.runtimeShell} -c 'set -eu; ip=\"$(${pkgs.tailscale}/bin/tailscale ip -4 \"$1\")\"; exec ${pkgs.tailscale}/bin/tailscale nc \"$ip\" \"$2\"' -- %h %p";
  };
in
{
  programs.ssh = {
    enable = true;
    settings = {
      "mac-home" = remote "mac-home";
      "yogabook" = remote "yogabook";
      "t480" = remote "t480-nixos";
    };
  };
}
