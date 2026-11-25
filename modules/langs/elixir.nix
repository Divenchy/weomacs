{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      beamPackages.expert
      beamPackages.elixir-ls
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      reformatter
      inf-elixir
      exunit
      mix
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-elixir.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-elixir}/parser";
      ".emacs.d/tree-sitter/libtree-sitter-heex.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-heex}/parser";
      ".emacs.d/lsp/langs/elixir.el".source = ../../emacs_elisp/lsp/langs/elixir.el;
    };
  };
}
