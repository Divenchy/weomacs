{
  flake.modules.homeManager.weomacs = {pkgs, ...}: let
    ats2-mode = pkgs.emacsPackages.trivialBuild {
      pname = "ats2-mode";
      version = "unstable";
      src = pkgs.runCommand "ats2-mode-src" { } ''
        mkdir $out
        cp ${pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/githwxi/ATS-Postiats/master/utils/emacs/ats2-mode.el";
          hash = "sha256-MB2swFvj/KfqMAMV0X4lxPQ+rOeF+dk9/4c1YhEmZIM=";
        }} $out/ats2-mode.el
      '';
    };
  in {
    programs.emacs.extraPackages = _: [ats2-mode];

    home.file.".emacs.d/lsp/langs/ats.el".source = ../../emacs_elisp/lsp/langs/ats.el;
  };
}
