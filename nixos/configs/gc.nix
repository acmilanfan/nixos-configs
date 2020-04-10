{ ... }: {

  nix.gc = {
    automatic = true;
    dates = "*:0/60";
  };

  systemd.services.nix-gc.unitConfig.ConditionACPower = true;
}
