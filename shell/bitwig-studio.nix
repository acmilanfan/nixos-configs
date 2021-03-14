{ pkgs ? import <nixpkgs> { config = { allowUnfree = true; }; } }:

pkgs.buildFHSUserEnv {
  name = "bitwig";
  targetPkgs = pkgs: (with pkgs;
    [ 
      bitwig-studio3
      xorg.libX11
      xorg.libxcb
      xorg.libXext
      xorg.libXinerama
      xlibs.libXi
      xlibs.libXcursor
      xlibs.libXdamage
      xlibs.libXcomposite
      xlibs.libXfixes
      xlibs.libXrender
      xlibs.libXtst
      xlibs.libXScrnSaver

      liblo
      zlib
      fftw
      minixml
      libcxx
      alsaLib
      glibc

      gtk2-x11
      atk
      mesa_glu
      glib
      pango
      gdk_pixbuf
      cairo
      freetype
      fontconfig
      dbus
    ]);
  runScript = "/usr/bin/bitwig-studio";
  profile = ''
    export LANG=en_US.UTF-8 
    export LD_LIBRARY_PATH=~/.nix-profile/lib:$LD_LIBRARY_PATH
    unset TZ
  '';
}
