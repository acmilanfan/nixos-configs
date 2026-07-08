{ ... }:

let secrets = import /Users/andreishumailov/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.ssh = {
    enable = true;
    settings."github-work" = {
      Hostname = "github.com";
      User = "git";
      IdentityFile = "~/.ssh/id_rsa";
      IdentitiesOnly = true;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.email = secrets.homeEmail;
      core.sshCommand = "ssh -i ~/.ssh/id_ed25519 -o 'IdentitiesOnly yes'";
      "url \"git@github.com:\"".insteadOf = "https://github.com/";
      "url \"git@github-work:wkda/\"" = {
        insteadOf = [
          "https://github.com/wkda/"
          "git@github.com:wkda/"
        ];
      };
    };
    includes = [
      {
        condition = "gitdir:~/Work/";
        contents = {
          user = {
            email = secrets.workEmail;
            name = "Andrei Shumailov";
          };
          core = { sshCommand = "ssh -i ~/.ssh/id_rsa -o 'IdentitiesOnly yes'"; };
        };
      }
    ];
  };

}
