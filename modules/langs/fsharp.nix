{
  flake.modules.homeManager.weomacs = {pkgs, ...}: let
    # nixpkgs only builds the fsharp grammar; fsharp-ts-mode also wants fsharp_signature for .fsi files
    tree-sitter-fsharp-signature = pkgs.tree-sitter.buildGrammar {
      language = "fsharp-signature";
      inherit (pkgs.tree-sitter-grammars.tree-sitter-fsharp) version src;
      location = "fsharp_signature";
    };
  in {
    home.packages = [pkgs.fsautocomplete];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      fsharp-ts-mode
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-fsharp.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-fsharp}/parser";
      ".emacs.d/tree-sitter/libtree-sitter-fsharp-signature.so".source = "${tree-sitter-fsharp-signature}/parser";
      ".emacs.d/lsp/langs/fsharp.el".source = ../../emacs_elisp/lsp/langs/fsharp.el;
    };
  };
}
