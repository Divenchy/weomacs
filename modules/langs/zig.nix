{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      zls
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      zig-mode
      zig-ts-mode
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-zig.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-zig}/parser";
      ".emacs.d/lsp/langs/zig.el".source = ../../emacs_elisp/lsp/langs/zig.el;
    };
  };
}
