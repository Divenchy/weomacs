{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      yaml-language-server
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      yaml-mode
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-yaml.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-yaml}/parser";
      ".emacs.d/lsp/langs/yaml.el".source = ../../emacs_elisp/lsp/langs/yaml.el;
    };
  };
}
