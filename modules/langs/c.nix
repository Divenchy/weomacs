{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      clang-tools
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-c.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-c}/parser";
      ".emacs.d/tree-sitter/libtree-sitter-cpp.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-cpp}/parser";
      ".emacs.d/lsp/langs/c.el".source = ../../emacs_elisp/lsp/langs/c.el;
    };
  };
}
