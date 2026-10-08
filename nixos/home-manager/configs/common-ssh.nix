{ ... }: {

  # settings blocks, not extraConfig: HM renders extraConfig under `Host *`,
  # and asserts settings."*" exists, which shell.nix only declares on darwin.
  programs.ssh = {
    enable = true;
    settings = {
      "github.com-secrets" = {
        HostName = "github.com";
        IdentityFile = "~/.ssh/id_ed25519";
      };

      "github.com-org" = {
        HostName = "github.com";
        IdentityFile = "~/.ssh/id_ed25519";
      };

      "github.com" = {
        HostName = "ssh.github.com";
        IdentityFile = "~/.ssh/id_ed25519";
        Port = 443;
      };
    };
  };

}
