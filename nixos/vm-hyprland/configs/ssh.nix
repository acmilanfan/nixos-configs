{ ... }: {

  # None of the real hosts run an SSH server (they're personal laptops), but
  # this VM is meant to be reachable from the Mac for remote-deploying config
  # changes (`nixos-rebuild switch --target-host`) without logging into it
  # directly. Authorize your key manually (e.g. `ssh-copy-id`) after first boot.
  services.openssh.enable = true;

}
