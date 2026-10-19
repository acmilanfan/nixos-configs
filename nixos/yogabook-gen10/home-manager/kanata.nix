{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    kanata
    (writeShellScriptBin "hypr-kanata-status" (lib.readFile ../../../dotfiles/waybar/scripts/kanata-status.sh))
  ];

  home.file = {
    ".config/kanata/kanata-yogabook.kbd".source =
      ../../../dotfiles/kanata/kanata-yogabook.kbd;
    ".config/kanata/kanata-disabled.kbd".source =
      ../../../dotfiles/kanata/kanata-disabled-linux.kbd;

    ".config/kanata/reload-kanata.sh" = {
      source = ../../../dotfiles/kanata/reload-kanata-linux.sh;
      executable = true;
    };
    ".config/kanata/switch-kanata.sh" = {
      source = ../../../dotfiles/kanata/switch-kanata-linux.sh;
      executable = true;
    };
    ".config/kanata/find-yogabook-kbd.sh" = {
      source = ../../../dotfiles/kanata/find-yogabook-kbd.sh;
      executable = true;
    };

    ".config/waybar/scripts/kanata-status.sh" = {
      source = ../../../dotfiles/waybar/scripts/kanata-status.sh;
      executable = true;
    };
  };

  # active_config.kbd is owned by switch-kanata.sh (ln -sf), not by HM, so the
  # chosen profile survives rebuilds. Only seed the default when it's missing
  # (after linkGeneration, which removes the link older generations managed).
  home.activation.seedKanataActiveConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    active="${config.xdg.configHome}/kanata/active_config.kbd"
    if [ ! -e "$active" ] && [ ! -L "$active" ]; then
      run mkdir -p $VERBOSE_ARG "$(dirname "$active")"
      run ln -s $VERBOSE_ARG "${config.xdg.configHome}/kanata/kanata-yogabook.kbd" "$active"
    fi
  '';

  # Auto-reload kanata on home-manager switch
  home.activation.reloadKanata = lib.hm.dag.entryAfter [ "writeBoundary" "seedKanataActiveConfig" ] ''
    if systemctl --user is-active kanata &>/dev/null; then
      run systemctl --user restart kanata
    fi
  '';

  systemd.user.services.kanata = {
    Unit = {
      Description = "Kanata keyboard remapper";
      Documentation = "https://github.com/jtroo/kanata";
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${pkgs.kanata}/bin/kanata --cfg %h/.config/kanata/active_config.kbd --port 5829";
      Restart = "on-failure";
      RestartSec = "5";
      StartLimitBurst = 10;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.zsh.shellAliases = {
    reload-kanata = "~/.config/kanata/reload-kanata.sh";
    switch-kanata = "~/.config/kanata/switch-kanata.sh";
    reload-kanata-logs = "journalctl --user -u kanata -f -n 50";
  };
}
