{
  pkgs,
  lib,
  ...
}:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # Auto-allow any .envrc under these roots - no manual `direnv allow` needed
    config.whitelist.prefix = [
      "~/Projects"
      "~/IdeaProjects"
      "~/Work/IdeaProjects"
    ];
  };

  # `use_tech` stdlib extension: picks the right devshell flake from project
  # marker files (go.mod / package.json / pom.xml / pyproject.toml / flake.nix)
  home.file.".config/direnv/direnvrc".source = ./direnv/direnvrc;

  # Bootstraps a project .envrc (`use_tech`); used by tmux-sessionizer
  home.packages = [
    (pkgs.writeShellScriptBin "tech-envrc" (lib.readFile ./scripts/tech-envrc))
  ];
}
