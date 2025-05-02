{ ... }: {

  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        theme = {
          activeBorderColor = [ "#9ece6a" "bold" ];
          inactiveBorderColor = [ "#3b4261" ];
          searchingActiveBorderColor = [ "#bb9af7" "bold" ];
          optionTextColor = [ "#7aa2f7" ];
          selectedLineBgColor = [ "#2c3043" ];
          selectedRangeBgColor = [ "#3b4261" ];
          cherryPickedCommitFgColor = [ "#9ece6a" ];
          cherryPickedCommitBgColor = [ "#283457" ];
          markedBaseCommitFgColor = [ "#7aa2f7" ];
          markedBaseCommitBgColor = [ "#e0af68" ];
          unstagedChangesColor = [ "#f7768e" ];
          defaultFgColor = [ "#c0caf5" ];
        };
      };
    };
  };

}

        # theme = {
        #   activeBorderColor = [ "#ff9e64" "bold" ];
        #   inactiveBorderColor = [ "#27a1b9" ];
        #   searchingActiveBorderColor = [ "#ff9e64" "bold" ];
        #   optionTextColor = [ "#7aa2f7" ];
        #   selectedLineBgColor = [ "#283457" ];
        #   cherryPickedCommitFgColor = [ "#7aa2f7" ];
        #   cherryPickedCommitBgColor = [ "#bb9af7" ];
        #   markedBaseCommitFgColor = [ "#7aa2f7" ];
        #   markedBaseCommitBgColor = [ "#e0af68" ];
        #   unstagedChangesColor = [ "#db4b4b" ];
        #   defaultFgColor = [ "#c0caf5" ];
        # };
