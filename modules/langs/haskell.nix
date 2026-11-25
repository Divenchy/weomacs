# ghc, cabal and HLS come from the nixweo haskell devshell (see emacs_elisp/lsp/langs/haskell.el).
{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    programs.emacs.extraPackages = epkgs: with epkgs; [
      haskell-ts-mode
      lsp-haskell
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-haskell.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-haskell}/parser";
      ".emacs.d/lsp/langs/haskell.el".source = ../../emacs_elisp/lsp/langs/haskell.el;
    };
  };
}
