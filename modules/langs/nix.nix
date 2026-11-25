{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = [pkgs.nil];
    programs.emacs.extraPackages = epkgs: [epkgs.nix-mode];
  };
}
