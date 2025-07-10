{
  description = "Java Dev Shell with Maven, Gradle, NodeJS, Docker";

  inputs.nixpkgs.url = "nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.x86_64-linux; [
        openjdk21
        maven
        gradle
        nodejs_22
        mariadb
      ];

      shellHook = ''
        export LANG=en_US.UTF-8
        export JAVA_HOME=${nixpkgs.legacyPackages.x86_64-linux.openjdk21}
        export PATH=$JAVA_HOME/bin:$PATH
        echo "Java DevShell ready."
      '';
    };
  };
}
