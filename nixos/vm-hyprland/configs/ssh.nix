{ ... }: {

  # None of the real hosts run an SSH server (they're personal laptops), but
  # this VM is meant to be reachable from the Mac for remote-deploying config
  # changes (`nixos-rebuild switch --target-host`) without logging into it
  # directly. It sits on a bridged network, i.e. the LAN, so key-only: the
  # Macs' public keys are in ./authorized_keys (append another Mac's
  # ~/.ssh/id_ed25519.pub there). Keys added earlier with ssh-copy-id keep
  # working; NixOS still reads ~/.ssh/authorized_keys.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.gentooway.openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];

}
