{ ... }: {

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  systemd.services.nix-gc.unitConfig.ConditionACPower = true;
}
