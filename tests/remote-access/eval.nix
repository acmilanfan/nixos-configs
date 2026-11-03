{ repo, manifest }:
let
  # Include only tracked files and explicitly reviewed new files without
  # staging. Never copy arbitrary untracked files or Git/project metadata.
  root = builtins.toPath repo;
  entries = builtins.fromJSON (builtins.readFile manifest);
  source = builtins.path {
    path = root;
    name = "remote-access-test-source";
    filter =
      path: _: builtins.elem (builtins.substring (builtins.stringLength repo + 1) 100000 path) entries;
  };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString source));
  home = config: user: {
    sshConfig = config.home-manager.users.${user}.home.file.".ssh/config".text;
    aliases =
      builtins.filter
        (name: builtins.hasAttr name config.home-manager.users.${user}.programs.ssh.settings)
        [
          "mac-home"
          "yogabook"
          "t480"
        ];
  };
  linux =
    host:
    let
      config = flake.nixosConfigurations.${host}.config;
    in
    {
      tailscale = config.services.tailscale.enable;
      ssh = config.services.openssh.enable;
      sshSettings = config.services.openssh.settings;
      sshOpenFirewall = config.services.openssh.openFirewall;
      globalTCPPorts = config.networking.firewall.allowedTCPPorts;
      tailnetTCPPorts = config.networking.firewall.interfaces.tailscale0.allowedTCPPorts or [ ];
      tailscaleOpenFirewall = config.services.tailscale.openFirewall;
      tailscaleSetFlags = config.services.tailscale.extraSetFlags;
      tailscaleSSHDisabled = config.systemd.services.tailscaled.environment.TS_DISABLE_SSH_SERVER or null;
      trustedInterfaces = config.networking.firewall.trustedInterfaces;
      reversePath = config.networking.firewall.checkReversePath;
      routing = config.services.tailscale.useRoutingFeatures;
      authKeyFile = config.services.tailscale.authKeyFile;
      inherit (config.networking) hostName;
      inherit (config.services.openssh) extraConfig;
      inherit (home config "gentooway") sshConfig aliases;
      failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
    };
  darwin =
    host: user:
    let
      config = flake.darwinConfigurations.${host}.config;
    in
    {
      tailscale = config.services.tailscale.enable;
      ssh = config.services.openssh.enable;
      sshExtraConfig = config.services.openssh.extraConfig;
      tailscaleAtBoot = config.launchd.daemons.tailscaled.serviceConfig.RunAtLoad or false;
      tailscaleSSHDisabled =
        config.launchd.daemons.tailscaled.serviceConfig.EnvironmentVariables.TS_DISABLE_SSH_SERVER or null;
      dnsOverride = config.services.tailscale.overrideLocalDns;
      inherit (home config user) sshConfig aliases;
      failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
    };
in
{
  mac-home = darwin "mac-home" "gentooway";
  mac-work = darwin "mac-work" "andreishumailov";
  yogabook = linux "yogabook-gen10";
  t480 = linux "t480-home";
  vm = linux "vm-hyprland";
}
