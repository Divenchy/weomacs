{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      gprbuild
      alire
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      ada-ts-mode
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-ada.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-ada}/parser";
      ".emacs.d/lsp/langs/ada.el".source = ../../emacs_elisp/lsp/langs/ada.el;
    };
  };
}
