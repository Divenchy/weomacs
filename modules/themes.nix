{
  flake.modules.homeManager.weomacs = {
    programs.emacs.extraPackages = epkgs: with epkgs; [
      doom-themes
      modus-themes
      ewal
      ef-themes
      sculpture-themes
      hyperstitional-themes
      creamsody-theme
    ];

    home.file.".emacs.d/themes.el".source = ../emacs_elisp/themes.el;
  };
}
