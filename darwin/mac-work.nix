{ pkgs, ... }:

{
  imports = [ ./common.nix ];

  system.primaryUser = "andreishumailov";

  networking.hostName = "mac-work";
}
