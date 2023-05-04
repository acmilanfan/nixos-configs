{ ... }: {

  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host github.com-secrets
        Hostname github.com
        IdentityFile=~/.ssh/id_ed25519

      Host github.com-org
        Hostname github.com
        IdentityFile=~/.ssh/id_ed25519

      Host github.com
        Hostname ssh.github.com
        IdentityFile=~/.ssh/id_ed25519
        Port 443
    '';
  };

}
