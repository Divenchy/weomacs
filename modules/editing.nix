{
  flake.modules.homeManager.weomacs = {
    programs.emacs.extraPackages = epkgs: with epkgs; [
      multiple-cursors
      avy
      expand-region
      hydra
      evil-nerd-commenter
    ];

    home.file = {
      ".emacs.d/remaps.el".source = ../emacs_elisp/remaps.el;
      ".emacs.d/visible-mark.el".source = ../emacs_elisp/visible-mark.el;
      ".emacs.d/dot-repeat.el".source = ../emacs_elisp/dot-repeat.el;
    };
  };
}
