{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  vicinaeSettings = {
    activate_on_single_click = true;
    close_on_focus_loss = true;
    consider_preedit = true;
    # Keep navigation state when the window closes. Among other things this
    # lets extension commands survive the browser taking focus during an
    # OAuth flow: the window hides on focus loss but the extension worker
    # stays alive, so the code->token exchange completes once the callback
    # is delivered (with true, closing the window popped to root and
    # unloaded the worker, losing the pending authorization).
    pop_to_root_on_close = false;
    favicon_service = "twenty";
    search_files_in_root = true;
    font = {
      normal = {
        size = 13;
        normal = "Roboto Medium";
      };
    };
    theme = {
      light = {
        name = "vicinae-light";
        icon_theme = "default";
      };
      dark = {
        # name = "vicinae-dark";
        name = "rose-pine";
        # name = "ayo-dark";
        icon_theme = "default";
      };
    };
    launcher_window = {
      opacity = 0.98;
    };
  };

  exts = inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system};

  # Extension names can be found in the link below, it's just the folder names
  # https://github.com/vicinaehq/extensions/tree/main/extensions
  linuxExtensions = [
    # bluetooth
    exts.nix
    exts.hypr-keybinds
  ];
  darwinExtensions = [
    exts.nix
    exts.pass
    exts.it-tools
    exts.jwt
    firefoxPatched
    exts.process-manager
    fuzzyFilesPatched
    exts.coffee
    exts.workspace
    exts.ollama-wordsmith
  ];

  # The firefox extension reads preferences.profile_dir at module load and may
  # receive a stale/platform-wrong value (the Linux default is not valid on
  # macOS). The source patch only honours the value when it actually contains
  # a profiles.ini and otherwise uses the platform default; the manifest
  # default is kept right for the preferences UI.
  firefoxPatched = patchManifest ''
    .preferences = [ .preferences[] |
      if .name == "profile_dir" then .default = "Library/Application Support/Firefox/" else . end ]
  '' (exts.firefox.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      python3 ${./patches/firefox-profile-dir.py}
      python3 ${./patches/firefox-history-range.py}
    '';
  }));

  # Raycast-store extensions, built from the exact upstream commit Raycast
  # built for the store (vicinae.lib.mkRayCastExtension runs `ray build` in
  # the sandbox). No local snapshots needed.
  #
  # To update an extension: query the store for its current commit, e.g.
  #   curl -s https://backend.raycast.com/api/v1/extensions/<author>/<name> | jq -r .source_url
  # then set `rev` to the commit and refresh `hash` by building with
  # hash = lib.fakeHash (the error reports the real hash), or use
  # nix-prefetch-git --sparse-checkout extensions/<name>.
  raycastExtensionSources = {
    audio-device = {
      author = "benvp";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      hash = "sha256-WCKWec009paYo9eFjuvBMWsXoc4Vt8nykeh10Sr+1AQ=";
    };
    brew = {
      author = "nhojb";
      rev = "79ab1cd6bc26bbc4e46cf6f5443a7aa3e70b1b77";
      hash = "sha256-00WO4nJ+Ls2l+BqYR0whVEOzJWR96YAwKcc3B5kCnas=";
    };
    downloads-manager = {
      author = "thomas";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      hash = "sha256-Xx2GmWDfmqgz2vkp3OMImuf2pQ3Jpns38MZ2OP7DvEo=";
    };
    gif-search = {
      author = "josephschmitt";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      hash = "sha256-Kkk0NbkPgNIntMP0TomdBkx4g1CosVMDvKBGYu24uR0=";
    };
    github = {
      author = "raycast";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      hash = "sha256-gO6Grma2xtbj1ICRgl0Kxo36ctoGsXISa3xHbRqqEbE=";
    };
    jira = {
      author = "raycast";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      hash = "sha256-U+SdV3Lt/MTn/THucN+DJNtDO6uHM9Drzp9M/U72nEM=";
    };
    mole = {
      author = "jlrochin";
      rev = "8a4409d03a593ea0b69b825b525c80753102a379";
      hash = "sha256-CVHlrSaYIiFSPfXTGz8x7xAVjwhg8juLjqHn5wnM4pc=";
    };
    opencode-sessions = {
      author = "mike182uk";
      rev = "ea6b73f98fa299a591da5994f73f3ca9d42a043d";
      hash = "sha256-aWk+Tve5VqCu127acYaGkJDbISUp6AcUnJOQsOoEHTU=";
    };
    port-manager = {
      author = "lucaschultz";
      rev = "521ebf98351b42c00d3f2a2dd52efa06c5c9b77a";
      hash = "sha256-EKNda+RYel+z3d3/YyTqr0JB3agmJpPFT3Hche/urm4=";
    };
    raycast-ollama = {
      author = "massimiliano_pasquini";
      rev = "5dc6bcaa699c431ea016d0b9b9ff6af5d1d7877e";
      hash = "sha256-9csLHGcwHDZYHU3idpo4ID9fBzCzh6cFvnkPodxLQrw=";
    };
    slack = {
      author = "mommertf";
      rev = "f7cf892382d20d12754d205db03fe1c38b2d0af3";
      hash = "sha256-KPWtfNeiZW0NvShPNKFY3mDgEn9z5JabwgnWtqpd3bk=";
    };
    toothpick = {
      author = "VladCuciureanu";
      rev = "7d0755b143096ce6042862f776701579cb7eda25";
      hash = "sha256-b43ZTyRmhHUKW7baHWmQTSN7drFau0JS+VMx2xPGH1w=";
    };
    video-downloader = {
      author = "vimtor";
      rev = "54094681ec05499b1db4c4f3ca12c14d30aa2359";
      hash = "sha256-4vF1NA/I8eyzQ5o8Z3DoD8kTab1l4UrHBW+DhLKapJM=";
    };
  };
  raycastExtensionBuilds = lib.mapAttrs (
    name: args:
    inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkRayCastExtension (
      { inherit name; } // args
    )
  ) raycastExtensionSources;

  # Extensions that can't use mkRayCastExtension: stale/broken lockfiles,
  # an npm `overrides` conflict (sips), or an old `ray` CLI that downloads
  # itself over the network (json-format). Built from the pinned upstream
  # commit in a network-enabled fixed-output derivation; see raycast-fod.nix.
  raycastFodExtensions = {
    sips = {
      author = "HelloImSteven";
      dir = "sips";
      rev = "8a4409d03a593ea0b69b825b525c80753102a379";
      sourceHash = "sha256-EoVFijnj/lYTDGLC6L1NqM+EsHLzIqIIeFRD4de4dTg=";
      outHash = "sha256-/nxgkl8xHsFzYeTHBylm24UjYT6cAjdDzbCdPHpXbnw=";
    };
    timers = {
      author = "ThatNerd";
      dir = "timers";
      rev = "351f1abf14bd550862b49e2cbfcd8d4b9fab901e";
      sourceHash = "sha256-DezVnKnlV+smsLzv3Js5ePXcmMI2NREPmErXT3cJZMw=";
      outHash = "sha256-yTU7I8q/FVJ9D2O5IWFc5pyZBpgVrVzLYW+A9/IbcHQ=";
      # The extension derives the "dismiss" file with
      #   masterName.replace(".timer", ".dismiss")
      # which replaces the FIRST match. Vicinae's support path ends with
      # "store.raycast.timers", so ".timer" matches inside the directory name
      # and produces "store.raycast.dismisss/…timer" -> ENOENT on timer start
      # when "Ring Continuously" is enabled. Anchor the replacement to the
      # file suffix instead.
      extraPostPatch = ''
        substituteInPlace src/backend/timerBackend.ts \
          --replace-fail 'replace(".timer", ".dismiss")' 'replace(/\.timer$/, ".dismiss")'
      '';
    };
    json-format = {
      author = "destiner";
      dir = "json-format";
      rev = "3c654737b0d566d3103fcdf72221a9f34664bdf2";
      sourceHash = "sha256-/EzEomPn1rlcb9fpdMxNvrKFNCg9+YyS93h08bARgyc=";
      outHash = "sha256-tiTypVpWcuhCkLnf6Gd38XLms0N0GuVcjY2I99+D/jc=";
    };
    translate = {
      author = "gebeto";
      dir = "google-translate";
      rev = "3a5a559d085c3e0dbf1dbe18fa4380030aa06793";
      sourceHash = "sha256-u9YxQINaolr5lH6tSwtrB+Hd9shm1f6xguRtaQPTx/o=";
      outHash = "sha256-qG9q+nIxOiBnua2msFU2cZZqillhJYPwAXOktdvwTRc=";
    };
  };
  raycastFodBuilds = lib.mapAttrs (
    name: args:
    import ./raycast-fod.nix (
      {
        inherit pkgs name;
      }
      // args
    )
  ) raycastFodExtensions;

  # Some extensions ship preference defaults that only work with Raycast
  # itself; patch the manifest defaults for this deployment (defaults are
  # read from package.json and shown/used as the initial value):
  #   timers:           the "Submarine" sound is a Raycast built-in that is
  #                     not part of the extension assets -> silent alarms.
  #   raycast-ollama:   input source defaults to "SelectedText", which mac
  #                     selection reading cannot provide -> default to the
  #                     clipboard with fallback enabled. (The source patch
  #                     below also forces the fallbacks at runtime, since the
  #                     manifest default is not guaranteed to be injected.)
  patchManifest =
    jqProgram: build:
    let
      prog = pkgs.writeText "raycast-manifest-patch.jq" jqProgram;
    in
    pkgs.runCommand build.name { } ''
      cp -r ${build}/. $out/
      chmod -R u+w $out
      ${pkgs.jq}/bin/jq -f ${prog} $out/package.json > $out/package.json.new
      mv $out/package.json.new $out/package.json
    '';
  # Source patches for extension bugs exposed by the Vicinae runtime (all
  # reported/patchable upstream):
  #   opencode-sessions: drives Ghostty via System Events keystrokes (needs
  #     Accessibility TCC a spawn helper can't get); patch to Ghostty's
  #     scripting API (new surface configuration + initial input). Resumed
  #     sessions also go through tmux when a tmux server is running.
  #   raycast-ollama: `values.mcp_server.length` crashes the chat command when
  #     the form's MCP server picker yields no value under Vicinae; make it
  #     optional. Also drops environment.canAccess guards (Vicinae reports
  #     selection/clipboard as inaccessible) and forces the input-source
  #     fallback so tone/explain commands work from the clipboard.
  raycastExtensionPatched = raycastExtensionBuilds // {
    opencode-sessions = raycastExtensionBuilds.opencode-sessions.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        python3 ${./patches/opencode-sessions-ghostty.py}
      '';
    });
    raycast-ollama = patchManifest ''
      .preferences = [ .preferences[] |
        if .name == "ollamaResultViewInput" then .default = "Clipboard"
        elif .name == "ollamaResultViewInputFallback" then .default = true
        else . end ]
    '' (raycastExtensionBuilds.raycast-ollama.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/lib/ui/ChatView/form/Model.tsx \
          --replace-fail 'values.mcp_server.length' 'values.mcp_server?.length'
        python3 ${./patches/raycast-ollama-canaccess.py}
      '';
    }));
  };
  raycastFodPatched = raycastFodBuilds // {
    timers = patchManifest ''
      .preferences = [ .preferences[] |
        if .name == "selectedSound" then .default = "alarmClock.wav" else . end ]
    '' raycastFodBuilds.timers;
  };

  # fuzzy-files resolves the default directory opener at module scope with no
  # catch; the rejection ("No default application found" on macOS) is an
  # unhandled rejection that kills the worker. Patch it to catch.
  fuzzyFilesPatched = exts.fuzzy-files.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      python3 ${./patches/fuzzy-files-default-app.py}
    '';
  });
in
lib.mkMerge [
  # Linux: full HM module — nix-built server via systemd, wrapped binary
  # carries VICINAE_OVERRIDES so it picks up `settings`.
  (lib.mkIf pkgs.stdenv.isLinux {
    programs.vicinae = {
      enable = true;
      settings = vicinaeSettings;
      systemd = {
        enable = true;
        autoStart = true; # default: false
        # environment = {
        #   USE_LAYER_SHELL = 1;
        # };
      };
      extensions = linuxExtensions;
    };
  })

  # macOS: do NOT enable the HM module. Enabling it installs the nix-built
  # Vicinae.app (~/Applications/Home Manager Apps), which:
  #   - collides with the brew-cask Vicinae.app in LaunchServices/Raycast
  #   - runs its CLI through a bash wrapper, so TCC attributes permission
  #     prompts to "bash" instead of "Vicinae" (and store hashes change on
  #     every rebuild, silently dropping grants).
  # We run the cask app (darwin-startup) and only deploy config + extensions.
  (lib.mkIf pkgs.stdenv.isDarwin {
    # Settings: the module would normally deliver these via VICINAE_OVERRIDES
    # baked into the nix binary; the cask app reads the overrides file
    # instead (exported via `launchctl setenv` in darwin-startup).
    home.file.".config/vicinae/nix.json".source =
      (pkgs.formats.json { }).generate "vicinae-nix-settings" vicinaeSettings;

    # Same deployment layout the module uses on Linux (~/.local/share/vicinae,
    # which the macOS app reads too). Plus script commands (~/.local/share/vicinae/scripts):
    # "Extract Text from Image" — OCR via the macOS Vision framework (JXA),
    # no Shortcut required.
    xdg.dataFile = lib.mkMerge [
      (builtins.listToAttrs (
        map (item: {
          name = "vicinae/extensions/${item.name}";
          value.source = item;
        }) darwinExtensions
      ))
      (builtins.listToAttrs (
        lib.mapAttrsToList (name: build: {
          name = "vicinae/extensions/store.raycast.${name}";
          value.source = build;
        }) raycastExtensionPatched
      ))
      (builtins.listToAttrs (
        lib.mapAttrsToList (name: build: {
          name = "vicinae/extensions/store.raycast.${name}";
          value.source = build;
        }) raycastFodPatched
      ))
      {
        "vicinae/scripts/extract-text-from-image.sh" = {
          source = ../../../dotfiles/vicinae/scripts/extract-text-from-image.sh;
          executable = true;
        };
        "vicinae/scripts/pass-otp.sh" = {
          source = ../../../dotfiles/vicinae/scripts/pass-otp.sh;
          executable = true;
        };
      }
    ];
  })
]
