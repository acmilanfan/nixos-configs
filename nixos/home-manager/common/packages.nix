{ pkgs, lib, ... }: {

  home.packages = with pkgs;
    [
      (writeShellScriptBin "ssh-add-login" (lib.readFile ./scripts/ssh-add-login.sh))
      (writeShellScriptBin "ns" (lib.readFile ./scripts/nixpkgs))
      (writeShellScriptBin "worktree-switch" (lib.readFile ./scripts/worktree-switch))
      (writeShellScriptBin "worktree-remove" (lib.readFile ./scripts/worktree-remove))
      (writeShellScriptBin "ai-agent-list" (lib.readFile ./scripts/ai-agent-list))
      # Python-backed AI tools: bundle the .py with its wrapper so the store
      # package is self-contained (uvx provides the `openai` SDK at runtime).
      (stdenv.mkDerivation {
        pname = "ai-bench";
        version = "0.1.0";
        src = ./.;
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/bin
          install -m755 ${./scripts/ai-bench} $out/bin/ai-bench
          install -m644 ${./scripts/qwen38-bench.py} $out/bin/qwen38-bench.py
        '';
      })
      (stdenv.mkDerivation {
        pname = "omlx-context-probe";
        version = "0.1.0";
        src = ./.;
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/bin
          install -m755 ${./scripts/omlx-context-probe} $out/bin/omlx-context-probe
          install -m644 ${./scripts/omlx-context-probe.py} $out/bin/omlx-context-probe.py
        '';
      })
      # bench-llm / llm-tap supersede ai-bench + omlx-context-probe above,
      # whose prompt-processing numbers are invalid (deterministic prompts hit
      # the engine prefix cache, so TTFT measured a cache hit, not a prefill).
      # See docs/superpowers/specs/2026-08-19-local-llm-prefill-design.md.
      # Stdlib-only, so no uvx/openai runtime dependency.
      (writers.writePython3Bin "bench-llm" { flakeIgnore = [ "E501" ]; }
        (lib.readFile ./scripts/bench-llm.py))
      (writers.writePython3Bin "llm-tap" { flakeIgnore = [ "E501" ]; }
        (lib.readFile ./scripts/llm-tap.py))
      git
      httpie
      kitty
      nixfmt
      htop
      yt-dlp
      clinfo
      jq
      scrcpy
      pandoc
      btop
      qmk
      bat
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      (writeShellScriptBin "ssh-askpass" ''
        ${pkgs.zenity}/bin/zenity --password --title="SSH Password"
      '')
      (writeShellScriptBin "screen-toggle"
        (lib.readFile ./scripts/screen-toggle))
      (writeShellScriptBin "touch-toggle" (lib.readFile ./scripts/touch-toggle))
      (writeShellScriptBin "try-lock" (lib.readFile ./scripts/try-lock))
      (python3.withPackages (ps: with ps; [ evdev ]))
      qmk-udev-rules
      vlc
      google-chrome
      android-tools
      mpv
      audacious
      calibre
      libreoffice
      pcmanfm
      arandr
      kdePackages.partitionmanager
      kdePackages.konsole
      kdePackages.dolphin
      networkmanagerapplet
      imv
      grim
      slurp
      playerctl
      pavucontrol
      lm_sensors
      zenity
      onboard
    ] ++ lib.optionals pkgs.stdenv.isDarwin [

    ] ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      # Real-hardware/gaming-focused packages that either only support
      # x86_64-linux (vial, libstrangle via lutris) or are meaningless on a VM
      # (thinkfan: real ThinkPad fan control; alsa-scarlett-gui: USB audio
      # interface hardware).
      vial
      lutris
      wineWow64Packages.full
      winetricks
      thinkfan
      proton-vpn
      alsa-scarlett-gui
    ];

  # TODO move
  programs.lf = {
    enable = true;
    previewer.source = pkgs.writeShellScript "bat-preview" ''
      #!/bin/sh
      file="$1"
      [ -d "$file" ] && exit 1
      bat --theme=nightfox --style=plain --color=always "$file"
    '';
    settings = { preview = true; };
  };

  programs.nix-search-tv = {
    enable = true;
  };

  home.file = {
    ".config/bat/themes/nightfox.tmTheme".source = pkgs.fetchurl {
      url =
        "https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/extra/nightfox/nightfox.tmTheme";
      sha256 = "sha256-J/0baDEYrV7on7qeHa4dIvLHPY4CH0lVLj4IR2G0pNs= ";
    };

    ".config/bat/config".text = ''
      --theme=nightfox
    '';
  };

}
