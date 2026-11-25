{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      metals
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      scala-ts-mode
      lsp-metals
      sbt-mode
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-scala.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-scala}/parser";
      ".emacs.d/lsp/langs/scala.el".source = ../../emacs_elisp/lsp/langs/scala.el;
    };
  };
}
