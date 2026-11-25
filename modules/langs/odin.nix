{
  flake.modules.homeManager.weomacs = {pkgs, ...}: let
    tree-sitter-odin = pkgs.tree-sitter.buildGrammar {
      language = "odin";
      version = "unstable";
      src = pkgs.fetchFromGitHub {
        owner = "amaanq";
        repo = "tree-sitter-odin";
        rev = "master";
        sha256 = "sha256-aPeaGERAP1Fav2QAjZy1zXciCuUTQYrsqXaSQsYG0oU=";
      };
    };
  in {
    programs.emacs.extraPackages = epkgs: [
      (epkgs.trivialBuild {
        pname = "odin-ts-mode";
        version = "unstable";
        src = pkgs.fetchFromGitHub {
          owner = "Sampie159";
          repo = "odin-ts-mode";
          rev = "master";
          sha256 = "/Zh1Xn5VknOqeKs7HTkMXS8sCq9NjZ56CtfKVWC8nyc=";
        };
      })
    ];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-odin.so".source = "${tree-sitter-odin}/parser";
      ".emacs.d/lsp/langs/odin.el".source = ../../emacs_elisp/lsp/langs/odin.el;
    };
  };
}
