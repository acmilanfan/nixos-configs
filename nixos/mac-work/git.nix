{ ... }:

let secrets = import /Users/andreishumailov/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.ssh = {
    enable = true;
    matchBlocks."github-work" = {
      hostname = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_rsa";
      identitiesOnly = true;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.email = secrets.homeEmail;
      core.sshCommand = "ssh -i ~/.ssh/id_ed25519 -o 'IdentitiesOnly yes'";
      "url \"git@github.com:\"".insteadOf = "https://github.com/";
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
