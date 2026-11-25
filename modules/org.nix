{
  flake.modules.homeManager.weomacs = {
    programs.emacs.extraPackages = epkgs: with epkgs; [
      org
      org-bullets
      visual-fill-column
    ];

    home.file.".emacs.d/org.el".source = ../emacs_elisp/org.el;
  };
}
