{ pkgs, ... }: {

  hardware.graphics = {
    enable32Bit = true;
  };

  hardware.openrazer.enable = true;

  # Set limits for esync.
  systemd.extraConfig = "DefaultLimitNOFILE=1048576";

  security.pam.loginLimits = [{
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "1048576";
  }];
}
