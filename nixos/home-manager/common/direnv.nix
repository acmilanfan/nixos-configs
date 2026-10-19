{
  pkgs,
  lib,
  ...
}:

{
  # No whitelist: a prefix whitelist ran any cloned repo's .envrc on `cd`
  # (including repos agents clone). tech-envrc and wt-setup grant trust for
  # the .envrc files they create or link; anything else needs `direnv allow`.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # One-time: keep trusting the .envrc files the old whitelist already covered,
  # so existing checkouts don't all start blocked. Only runs once (marker), so
  # repos cloned later are not swept in.
  home.activation.direnvTrustExisting = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    marker="''${XDG_STATE_HOME:-$HOME/.local/state}/direnv/whitelist-migrated"
    if [ ! -e "$marker" ]; then
      for root in "$HOME/Projects" "$HOME/IdeaProjects" "$HOME/Work/IdeaProjects"; do
        [ -d "$root" ] || continue
        find "$root" -maxdepth 3 -name .envrc 2>/dev/null | while IFS= read -r rc; do
          run ${pkgs.direnv}/bin/direnv allow "$(dirname "$rc")" || true
        done
      done
      run mkdir -p "$(dirname "$marker")"
      run touch "$marker"
    fi
  '';

  # `use_tech` stdlib extension: picks the right devshell flake from project
  # marker files (go.mod / package.json / pom.xml / pyproject.toml / flake.nix)
  home.file.".config/direnv/direnvrc".source = ./direnv/direnvrc;

  # Bootstraps a project .envrc (`use_tech`); used by tmux-sessionizer
  home.packages = [
    (pkgs.writeShellScriptBin "tech-envrc" (lib.readFile ./scripts/tech-envrc))
  ];
}
