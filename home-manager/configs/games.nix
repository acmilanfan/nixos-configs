{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    winetricks
    #appimage-run
    wineWowPackages.full
    lutris
    #lutris-free

    xorg.xkbcomp
    razergenie

    # battle net deps
    gnutls
    libgpgerror
    sqlite
    p11-kit
    readline
    libusb1
    openldap

    vulkan-tools
    vulkan-loader
    vulkan-headers
    vulkan-tools-lunarg
    vulkan-extension-layer
    vulkan-validation-layers 

    discord
  ];

}
