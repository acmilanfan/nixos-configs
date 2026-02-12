{ ... }:

let secrets = import /Users/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    settings = {
      user.email = secrets.homeEmail;
      core = {
        sshCommand = "ssh -i ~/.ssh/id_ed25519 -o 'IdentitiesOnly yes'";
      };
    };
  };

}
