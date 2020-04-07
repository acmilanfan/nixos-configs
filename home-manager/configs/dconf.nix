{ lib, ... }: {


  dconf.settings = {
    "org/gnome/settings-daemon/plugins/xsettings" = {
      antialiasing="rgba";
      hinting="medium";
    };
    "org/gnome/mutter" = {
      center-new-windows=true;
      workspaces-only-on-primary=true;
    };
    "org/gnome/desktop/interface" = {
      clock-show-date=true;
      clock-show-seconds=false;
      clock-show-weekday=false;
      cursor-theme="DMZ-Black";
      enable-animations=true;
      gtk-im-module="gtk-im-context-simple";
      gtk-theme="Adwaita-dark";
      show-battery-percentage=false;
    };
    "org/gnome/desktop/wm/preferences" = {
      auto-raise=false;
      button-layout="appmenu:close";
      focus-mode="sloppy";
      mouse-button-modifier="<Super>";
      resize-with-right-button=false;
    };
    "org/gnome/desktop/input-sources" = {
      per-window=false;
      show-all-sources=false;
      # todo this will work afte 20.03 release
      #sources=[ 
      #  lib.hm.gvariant.mkTuple ["xkb" "us"] 
      #  lib.hm.gvariant.mkTuple ["xkb" "de"] 
      #  lib.hm.gvariant.mkTuple ["xkb" "ru"] 
      #];
      xkb-options=["grp:alt_space_toggle"];
    };
    "org/gnome/shell/keybindings" = {
      toggle-application-view=["<Super>d"];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      screensaver=["<Primary><Super>l"];
    };
    "org/gnome/mutter/keybindings" = {
      toggle-tiled-left=["<Primary><Super>Left"];
      toggle-tiled-right=["<Primary><Super>Right"];
    };
    "org/gnome/desktop/wm/keybindings" = {
      close=["<Shift><Super>c"];
      maximize=["<Primary><Super>Up"];
      move-to-monitor-down=["@as []"];
      move-to-monitor-up=["@as []"];
      move-to-workspace-down=["<Shift><Super>Down"];
      move-to-workspace-up=["<Shift><Super>Up"];
      switch-to-workspace-down= ["<Super>Down"];
      switch-to-workspace-up=["<Super>Up"];
      toggle-fullscreen=["<Super>f"];
      unmaximize=["<Primary><Super>Down"];
      activate-window-menu=["@as []"];
      begin-resize=["<Super>r"];
      move-to-monitor-left=["@as []"];
      move-to-monitor-right=["@as []"];
      switch-input-source=["<Alt>space"];
      switch-input-source-backward=["<Shift><Alt>space"];
      switch-to-workspace-left=["@as []"];
      switch-to-workspace-right=["@as []"];
      toggle-maximized=["@as []"];
    };
    "org/gnome/desktop/search-providers" = {
      sort-order=["org.gnome.Contacts.desktop" "org.gnome.Documents.desktop"  "org.gnome.Nautilus.desktop"];
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      click-method="fingers";
      edge-scrolling-enabled=false;
      tap-to-click=true;
      two-finger-scrolling-enabled=true;
    };
    "system/locale" = {
      region="en_GB.UTF-8";
    };  
  };

}
