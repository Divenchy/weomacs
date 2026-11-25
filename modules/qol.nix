{
  flake.modules.homeManager.weomacs = {
    programs.emacs.extraPackages = epkgs: with epkgs; [
      doom-modeline
      rainbow-delimiters
      which-key
      helpful
      command-log-mode
      vertico
      vertico-posframe
      posframe
      vertico-prescient
      prescient
      orderless
      marginalia
      consult
      embark
      embark-consult
      wgrep
      ripgrep
      undo-fu
      undo-fu-session
      gcmh
      stripspace
      nerd-icons-dired
      pdf-tools
    ];

    home.file.".emacs.d/qol.el".source = ../emacs_elisp/qol.el;
  };
}
