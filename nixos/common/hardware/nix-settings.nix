{ lib, ... }: {

  nix.settings.max-jobs = lib.mkDefault 8;

}
