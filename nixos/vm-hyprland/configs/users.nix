{ ... }: {

  users.users.gentooway = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    # Only the real hosts (yogabook-gen10/t480-home/z16) set no password
    # declaratively, since whoever sets those up has physical console access
    # to run `passwd` once. This VM image boots with no prior activation, so
    # without this the account would likely be locked on first boot.
    # initialPassword only applies on first activation (not re-applied on
    # rebuilds) - change it immediately after logging in via `passwd`.
    initialPassword = "changeme";
  };

}
