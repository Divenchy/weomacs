{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
      csharp-ls
      netcoredbg
      rsync
    ];

    programs.emacs.extraPackages = epkgs: with epkgs; [
      dotnet
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-c-sharp.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-c-sharp}/parser";
      ".emacs.d/lsp/langs/csharp.el".source = ../../emacs_elisp/lsp/langs/csharp.el;
    };
  };
}
