{ stdenv, fetchurl, lib, makeWrapper, writeShellScript, ... }:

let
  version = "1.3.5";
  src-osx = fetchurl {
    url = "https://github.com/rvaiya/warpd/releases/download/v${version}/warpd-${version}-osx.tar.gz";
    sha256 = "0azvib927yqyp0cdlq5qk4h7pikxv2yl3n1v7mdx8k467bmvljsa";
  };

  # The actual binary derivation
  warpd-bin = stdenv.mkDerivation {
    pname = "warpd-bin";
    inherit version;
    src = src-osx;
    unpackPhase = "tar -xzvf $src";
    installPhase = ''
      mkdir -p $out/bin $out/share/man/man1
      cp ./usr/local/bin/warpd $out/bin/
      cp ./usr/local/share/man/man1/warpd.1.gz $out/share/man/man1/
    '';
  };

  # AppleScript launcher to handle the daemon
  launcher = writeShellScript "warpd-launcher" ''
    # If warpd is already running, do nothing (daemon mode -f handles this, but it's cleaner)
    if pgrep -x "warpd" > /dev/null; then
      exit 0
    fi
    # Use the stable binary path copied by nix-darwin activation
    if [ -x "/usr/local/bin/warpd-nix" ]; then
      exec /usr/local/bin/warpd-nix -f
    else
      # Fallback to store path
      exec ${warpd-bin}/bin/warpd -f
    fi
  '';

in
stdenv.mkDerivation {
  pname = "warpd";
  inherit version;

  inherit (warpd-bin) src;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/Applications/Warpd.app/Contents/MacOS
    mkdir -p $out/Applications/Warpd.app/Contents/Resources
    mkdir -p $out/bin

    # Link the CLI binary
    ln -s ${warpd-bin}/bin/warpd $out/bin/warpd

    # Create the App wrapper
    cp ${launcher} $out/Applications/Warpd.app/Contents/MacOS/Warpd

    # Create Info.plist
    cat <<EOF > $out/Applications/Warpd.app/Contents/Info.plist
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>Warpd</string>
        <key>CFBundleIconFile</key>
        <string>Warpd</string>
        <key>CFBundleIdentifier</key>
        <string>com.warpd.warpd</string>
        <key>CFBundleName</key>
        <string>Warpd</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>LSBackgroundOnly</key>
        <true/>
    </dict>
    </plist>
    EOF
  '';

  meta = with lib; {
    description = "Modal keyboard driven interface for mouse manipulation (Application Wrapper)";
    homepage = "https://github.com/rvaiya/warpd";
    platforms = platforms.darwin;
    license = licenses.mit;
  };
}
