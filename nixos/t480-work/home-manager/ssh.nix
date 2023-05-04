{ ... }: {

  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host github.com-secrets
        Hostname github.com
        IdentityFile=~/.ssh/id_rsa

      Host github.com-org
        Hostname github.com
        IdentityFile=~/.ssh/id_rsa

      Host github.com-nixos-configs
        Hostname github.com
        IdentityFile=~/.ssh/id_rsa

      Host github.com
        Hostname ssh.github.com
        IdentityFile=~/.ssh/id_rsa
        Port 443
    '';
  };

}
