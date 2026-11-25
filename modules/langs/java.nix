{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      jdt-language-server
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      lsp-java
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-java.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-java}/parser";
      ".emacs.d/lsp/langs/java.el".source = ../../emacs_elisp/lsp/langs/java.el;
    };
  };
}
