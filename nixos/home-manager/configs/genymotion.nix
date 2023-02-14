{ pkgs, ... }:

let

  packages = with pkgs; [
    libpulseaudio libsForQt5.qca-qt5 stdenv.cc.cc zlib glib xorg.libX11 libxkbcommon xorg.libXmu xorg.libXi xorg.libXext libGL xorg.libxcb fontconfig.lib freetype systemd 
  ];
  libPath = pkgs.lib.makeLibraryPath packages;

in {

  allowUnfree = true;

  packageOverrides = pkgs: {
    genymotion = pkgs.genymotion.overrideAttrs ( 
      _: rec { 
        version = "3.2.1"; 
        src = pkgs.fetchurl {
          url = "https://dl.genymotion.com/releases/genymotion-${version}/genymotion-${version}-linux_x64.bin";
          name = "genymotion-${version}-linux_x64.bin";
          sha256 = "0lz4pl2mh77d297dn2z22l65wy5n3mihx35b76yynwlcz18k69y8";
        };
        
      nativeBuildInputs = [ pkgs.qt5.wrapQtAppsHook pkgs.qt5.qttools pkgs.which ];

      buildInputs = [ pkgs.makeWrapper pkgs.xdg_utils ];

      fixupPhase = ''
        patchInterpreter() {
         patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            "$out/libexec/genymotion/$1"
        }
        patchExecutable() {
         patchInterpreter "$1"
         wrapQtApp "$out/libexec/genymotion/$1" \
            --set "LD_LIBRARY_PATH" "${libPath}" \
            --prefix QT_XKB_CONFIG_ROOT ":" "${pkgs.xorg.xkeyboardconfig}/share/X11/xkb"
        }
        patchTool() {
         patchInterpreter "tools/$1"
         wrapQtApp "$out/libexec/genymotion/tools/$1" \
            --set "LD_LIBRARY_PATH" "${libPath}" \
            --prefix QT_XKB_CONFIG_ROOT ":" "${pkgs.xorg.xkeyboardconfig}/share/X11/xkb"
        }
        patchExecutable genymotion
         patchExecutable player
         patchTool adb
         patchTool aapt
         patchTool glewinfo
        '';

      installPhase = ''
          mkdir -p $out/bin $out/libexec
          mv genymotion $out/libexec/

          ln -s $out/libexec/genymotion/{genymotion,player} $out/bin
        '';
      }  
    );

  };
  
}
