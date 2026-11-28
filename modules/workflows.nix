{
  flake.modules.homeManager.weomacs = {pkgs, ...}: let
    claude-code-ide = pkgs.emacsPackages.trivialBuild {
      pname = "claude-code-ide";
      version = "unstable";
      src = pkgs.fetchFromGitHub {
        owner = "manzaltu";
        repo = "claude-code-ide.el";
        rev = "50a3d55262805d7207889ed429ff30da96fbf68b";
        hash = "sha256-u+87PjLh0Mc7C8nvDG758rdgpmjED8G/hO+FE1tj7DU=";
      };
      packageRequires = with pkgs.emacsPackages; [websocket transient web-server ghostel];
      # Tests pull in extra deps and aren't needed at runtime
      postUnpack = ''
        rm $sourceRoot/claude-code-ide-tests.el
      '';
    };
  in {
    programs.emacs.extraPackages = epkgs:
      (with epkgs; [
        envrc
        magit
        projectile
        ghostel
      ])
      ++ [claude-code-ide];

    home.file.".emacs.d/workflows.el".source = ../emacs_elisp/workflows.el;
  };
}
