{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = [pkgs.rust-analyzer];
    programs.emacs.extraPackages = epkgs: [epkgs.rust-mode];
  };
}
