{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    winetricks
    #appimage-run
    wineWow64Packages.full
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
