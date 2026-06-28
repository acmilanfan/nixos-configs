{ pkgs ? import <nixpkgs> {
  overlays = [ (self: super: { jdk = super.jetbrains.jdk; }) ];
} }:

let
  # selectedJDK = pkgs.openjdk11;
  selectedJDK = pkgs.openjdk21;
  # selectedJDK = pkgs.openjdk23;

  fhs = pkgs.buildFHSEnv {
    name = "java-maven-env";
    targetPkgs = pkgs:
      (with pkgs; [
        maven
        zlib
        pam
        gdb
        xorg.libXext
        xorg.libX11
        xorg.libXrender
        xorg.libXtst
        xorg.libXi
        freetype
        gradle
        libaio
        numactl
        ncurses5
        libxcrypt
        libxcrypt-legacy
        nodejs_22
        mocha
        typescript
        docker
        openssl
        glibc
        mariadb.client
        glibcLocales
        gnumake
        mariadb
        systemd
      ]);
    runScript = "zsh";
  };

in pkgs.stdenv.mkDerivation {
  name = "maven-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    export PATH=$PATH:/run/current-system/bin
    export DOCKER_CONFIG=/etc/docker/config.json
    sudo systemctl start docker
    sudo systemctl is-active --quiet docker && echo "Docker is running" || echo "Failed to start Docker"
    sudo chmod 666 /var/run/docker.sock
    export DOCKER_HOST=unix:///var/run/docker.sock

    export JAVA_HOME=${selectedJDK}
    export PATH=$JAVA_HOME/bin:$PATH

    exec java-maven-env
  '';
}
