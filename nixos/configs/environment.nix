{ ... }: {

  environment.variables = {
    BROWSER="firefox";
    EDITOR="vim";
    MOZ_USE_XINPUT2="1";

    #todo wayland config
    MOZ_ENABLE_WAYLAND="1";
    QT_QPA_PLATFORM="wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION="1";
    #WLR_DRM_NO_MODIFIERS="1";
  };

  environment.shellAliases = {
    # todo move it to home manager or expose through environment variable
    repass = "PASSWORD_STORE_DIR=$HOME/configs/secrets pass";
  };

}
