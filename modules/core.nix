{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    programs.emacs = {
      enable = true;
      package = pkgs.emacs;
      extraPackages = epkgs: with epkgs; [
        exec-path-from-shell
        ligature
      ];
    };

    home.file = {
      ".emacs.d/early-init.el".source = ../emacs_elisp/early-init.el;
      ".emacs.d/init.el".source = ../emacs_elisp/init.el;
      ".emacs.d/basic_settings.el".source = ../emacs_elisp/basic_settings.el;
    };
  };
}
