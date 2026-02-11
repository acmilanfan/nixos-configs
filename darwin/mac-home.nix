{ pkgs, ... }:

{
  imports = [ ./common.nix ];

  system.primaryUser = "gentooway";

  networking.hostName = "mac-home";
}
